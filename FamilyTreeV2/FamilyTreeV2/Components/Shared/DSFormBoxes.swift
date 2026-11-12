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
        return VStack(alignment: .leading, spacing: DS.Spacing.smd) {
            HStack(spacing: DS.Spacing.sm) {
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
    /// اختيار الجنس: زرّان أنيقان بارتفاع أزرار المربّعات (طلب المالك ٢٠٢٦-١١-٠٦)
    static let genderHeight: CGFloat = 44
    static let genderHeightInBox: CGFloat = 40
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
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(label)
                .dsFieldFont(DSBox.fieldLabelSize, weight: DS.TextRole.label.weight)
                .foregroundColor(DS.Color.fieldLabel)
            content()
                .dsFieldFont(DSBox.fieldValueSize, weight: DS.TextRole.fieldValue.weight)
                .foregroundColor(DS.Color.textPrimary)
                .dsFieldChrome()
        }
    }
}

/// مفتاح (تشغيل/إيقاف) داخل مربّع
struct DSToggleBox: View {
    let title: String
    @Binding var isOn: Bool
    var tint: Color = DS.Color.toggleOn

    var body: some View {
        Toggle(isOn: $isOn.animation(DS.Anim.snappy)) {
            Text(title)
                .dsFieldFont(.bodyMedium)
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
            .dsFieldFont(.label)
            .foregroundColor(DS.Color.fieldLabel)
    }
}

// MARK: - التواريخ: صف للقراءة + مربّع اختيار بالمنتصف (طلب المالك)

enum DSDateText {
    /// «23/09/2026» — الصيغة الموحّدة (`DateHelper.displayDate`)
    static func display(_ date: Date) -> String { DateHelper.displayDate(date) }
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
        DSCenterCard(onBackgroundTap: onCancel, title: title, icon: "calendar", maxWidth: DSBox.dateCardMaxWidth) {

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

    /// خيار «حيّ» في اختيار الحالة
    var aliveTitle: String = L10n.t("على قيد الحياة", "Alive")

    var body: some View {
        // خلايا البيانات الموحّدة (`DSTileGrid`، قرار المالك ٢٠٢٦-١١-١١ «مربّعات متجاورة»): الميلاد والحالة متجاوران،
        // و«تاريخ الوفاة» يظهر بعد الحالة مباشرة حين تُختار الوفاة
        var items: [DSTileItem] = [
            .half(DSDateFieldRow(icon: "calendar", title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                 hasDate: hasBirthDate, dateText: DSDateText.display(birthDate),
                                 onEdit: { pick(title: L10n.t("تاريخ الميلاد", "Birth Date"), has: $hasBirthDate, date: $birthDate) }))
        ]
        if showsDeceased {
            items.append(.half(DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
                DSChoiceOption(id: false, title: aliveTitle, icon: "heart.fill"),
                DSChoiceOption(id: true, title: deceasedTitle, icon: "leaf.fill")
            ], selection: $isDeceased.animation(DS.Anim.snappy))))
            if isDeceased {
                items.append(.half(DSDateFieldRow(icon: "calendar.badge.minus", title: L10n.t("تاريخ الوفاة", "Death Date"),
                                                  hasDate: hasDeathDate, dateText: DSDateText.display(deathDate),
                                                  onEdit: { pick(title: L10n.t("تاريخ الوفاة", "Death Date"), has: $hasDeathDate, date: $deathDate) })))
            }
        }
        return DSTileGrid(items)
    }

    /// المنتقي الموحّد — «بدون تاريخ» زرّ داخله (لا في الخلية)، يظهر حين يوجد تاريخ
    private func pick(title: String, has: Binding<Bool>, date: Binding<Date>) {
        dsPresentDatePicker(title: title,
                            initial: has.wrappedValue ? date.wrappedValue : nil,
                            allowClear: has.wrappedValue) { picked in
            if let picked {
                date.wrappedValue = picked
                has.wrappedValue = true
            } else {
                has.wrappedValue = false
            }
        }
    }
}

// MARK: - الجنس: بطاقتان بأيقونة بدل المبدّل (طلب المالك)

struct DSGenderPicker: View {
    @Binding var selection: String
    /// نجمة «مطلوب» الحمراء بجانب العنوان (مثل حقول التسجيل) — الاختيار الفارغ «» = لا شيء محدّد
    var required: Bool = false
    @Environment(\.dsInCenterBox) private var inBox

    /// زرّان «ذكر · أنثى» (شريط الاختيار) بدل الخلية بقائمة — مربّع «إضافة فرد» (قرار المالك ٢٠٢٦-١١-١١)
    var buttons: Bool = false

    private var options: [DSChoiceOption<String>] {
        [DSChoiceOption(id: "male", title: L10n.t("ذكر", "Male"), icon: "figure.stand"),
         DSChoiceOption(id: "female", title: L10n.t("أنثى", "Female"), icon: "figure.stand.dress")]
    }

    var body: some View {
        if buttons {
            DSChoiceTile(icon: "figure.stand", label: L10n.t("الجنس", "Gender") + (required ? " *" : ""),
                         options: options, selection: $selection)
        } else {
            // خلية بيانات بقائمة (قرار المالك ٢٠٢٦-١١-١١) — الاختيار الفارغ «» يعرض «اختر»
            DSMenuTile(icon: "figure.stand", label: L10n.t("الجنس", "Gender") + (required ? " *" : ""),
                       options: options, selection: $selection)
        }
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

// MARK: - العناصر الموحّدة لمربّعات البيانات (طلب المالك ٢٠٢٦-١١-١٠ «التصاميم مو موحدة»)
//
// القواعد: كل اختيار من خيارين/ثلاثة = `DSChoiceTiles` (المختار ممتلئ بكحلي القسم ونصّ أبيض، وغيره سطح
// البطاقة بإطار رفيع — لون واحد لكل الاختيارات بلا أخضر)؛ كل صفّ حقل = صندوق الصفوف (`dsRowBox`) +
// `DSFieldIcon` + العنوان (`label`) + القيمة (`fieldValue`)؛ صفّ التاريخ `DSDateFieldRow` بقلم واحد دائماً.
// الرموز: الاسم person.fill · الهاتف phone.fill · الميلاد calendar · الوفاة calendar.badge.minus ·
// الحالة (حيّ/متوفى) leaf.fill · الحالة الاجتماعية heart.fill · الخصوصية lock.fill.

/// خيار واحد في `DSChoiceTiles`
struct DSChoiceOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var icon: String? = nil
}

/// الاختيار الموحّد من خيارين أو ثلاثة — مبدّل مقاطع خفيف واحد (طلب المالك ٢٠٢٦-١١-١٠ «تبسيط الأزرار بشكل سلس
/// وخفيف»): مسار رمادي فاتح واحد بارتفاع ~٣٦، والمختار حبّة بيضاء بظلّ ناعم جداً ونصّ كحلي، وغيره نصّ ثانوي؛
/// الحبّة تنزلق بين الخيارات بنابض هادئ (بلا حركة مع «تقليل الحركة»). مساحة اللمس ٤٤ رغم الارتفاع المرئي الأصغر.
/// السؤال الاختياري فوقه وسطر الشرح تحته بنصّ صغير ثانوي. بأحجام إمكانية الوصول: الخيارات فوق بعض بنفس الخفّة.
struct DSChoiceTiles<ID: Hashable>: View {
    var label: String? = nil
    let options: [DSChoiceOption<ID>]
    @Binding var selection: ID
    var note: String? = nil
    /// المقاس المضغوط في طرف صفّ: عرض ثابت (`DSBox.choiceCompactWidth`) ومسار أقصر — نفس الحبّة والإطار، واللمس ٤٤
    var compact: Bool = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dsSection) private var section
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var pill
    @Environment(\.dsInCenterBox) private var inBox

    /// الارتفاع المرئي للمقطع (اللمس ٤٤ بالحشوة الشفافة) — في الصفحات أقصر (`choicePageHeight`)
    static var segmentHeight: CGFloat { DSBox.choiceTrackHeight }
    private var height: CGFloat {
        compact ? DSBox.choiceCompactHeight : (inBox ? Self.segmentHeight : DSBox.choicePageHeight)
    }
    private var trackInset: CGFloat { DSBox.choiceTrackInset }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if let label {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let stack = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 0))
                : AnyLayout(HStackLayout(spacing: 0))
            stack { ForEach(options) { segment($0) } }
                .padding(trackInset)
                // المضغوط داخل صفّ حقل رمادي: مساره بلون سطح البطاقة ليتميّز عن الصفّ
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(compact ? DS.Color.surface : DS.Color.fieldFill))
                .frame(width: compact && !typeSize.isAccessibilitySize ? DSBox.choiceCompactWidth : nil)
            if let note {
                Text(note)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func segment(_ option: DSChoiceOption<ID>) -> some View {
        let selected = selection == option.id
        let ink = DS.Color.primary.dsChrome(in: section).dsReadableGlyph
        let pillShape = RoundedRectangle(cornerRadius: DS.Radius.md - trackInset, style: .continuous)
        return Button {
            guard !selected else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) { selection = option.id }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if let icon = option.icon {
                    Image(systemName: icon)
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(selected ? ink : DS.Color.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(option.title)
                    .dsFieldFont(inBox ? .fieldValue : DSBox.choicePageText)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundColor(selected ? DS.Color.textPrimary : DS.Color.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background {
                if selected {
                    // علامة المختار (قرار المالك ٢٠٢٦-١١-١١): حبّة `choicePill` بإطار كحلي ١ نقطة (`selectionStroke`)
                    pillShape
                        .fill(DS.Color.choicePill)
                        .overlay(pillShape.strokeBorder(DS.Color.selectionStroke, lineWidth: DS.Border.width))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: DSBox.choiceShadowRadius, y: DSBox.choiceShadowY)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            // مساحة لمس ٤٤ رغم الارتفاع المرئي الأصغر
            .padding(.vertical, max(0, (DS.Icon.tapTarget - height) / 2 - trackInset))
            .contentShape(Rectangle())
            .padding(.vertical, -max(0, (DS.Icon.tapTarget - height) / 2 - trackInset))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// صفّ التاريخ الموحّد (الميلاد، الوفاة) — بنفس صندوق صفوف الحقول، والقلم يفتح المنتقي؛
/// «بدون تاريخ» شريحة غير مختارة تظهر حين يوجد تاريخ فقط (لمسحه)
struct DSDateFieldRow: View {
    let icon: String
    let title: String
    let hasDate: Bool
    let dateText: String
    /// (لم يعد يُعرض في الخلية — «بدون تاريخ» زرّ داخل منتقي التاريخ: `dsPresentDatePicker(allowClear:)`)
    var onClear: (() -> Void)? = nil
    let onEdit: () -> Void

    var body: some View {
        // خلية البيانات الواحدة: عنوان صغير + القيمة + قلم (يُكتب/يُختار تاريخه)
        Button(action: onEdit) {
            DSFieldTileFace(icon: icon, label: title,
                            value: hasDate ? dateText : L10n.t("بدون تاريخ", "No date"),
                            isPlaceholder: !hasDate, glyph: .edit)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح اختيار التاريخ", "Opens the date picker"))
    }
}

// MARK: - خلية البيانات الواحدة وشبكتها (قرار المالك ٢٠٢٦-١١-١١ «د — مربّعات متجاورة»)
//
// القاعدة الواحدة: كل معلومة في المربّع خلية من نوع واحد — (رمز صغير اختياري) + عنوان صغير رمادي + القيمة تحته + رمز واحد
// في الطرف: قلم = تُكتب أو يُختار تاريخها، سهم = تفتح قائمة خيارات. نفس التعبئة (`fieldFill`) والزوايا والارتفاع والخطوط،
// بلا إطارات ولا شرائح داخل الخلية. الشبكة `DSTileGrid`: القصيرة خليتان متجاورتان، والطويلة (`wide`) أو الفردية الباقية
// بعرض السطر، ومن حجم الخط xxLarge كل شيء عمود واحد. الخلية المتجاورة بلا رمز البداية.

/// الرمز الواحد في طرف الخلية
/// `open`: سهم باتجاه القراءة — الخلية تفتح تفاصيل (العضو…)
enum DSTileGlyph { case edit, menu, open, none }

private struct DSTileHalfKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// الخلية في نصف السطر (عمودان) — تُسقط رمز البداية
    var dsTileHalf: Bool {
        get { self[DSTileHalfKey.self] }
        set { self[DSTileHalfKey.self] = newValue }
    }
}

/// وجه خلية البيانات — يُلبس `Button` (قلم) أو `Menu` (سهم)
struct DSFieldTileFace: View {
    var icon: String? = nil
    let label: String
    let value: String
    var isPlaceholder: Bool = false
    var glyph: DSTileGlyph = .edit
    /// القيمة أرقام لاتينية (هاتف) — من اليسار لليمين
    var ltrValue: Bool = false
    @Environment(\.dsTileHalf) private var half
    @Environment(\.dsSection) private var section

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if let icon, !half {
                DSFieldIcon(name: icon).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.tileLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(value)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(isPlaceholder ? DS.Color.textTertiary : DS.Color.tileValue)
                    .lineLimit(half ? 1 : 2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .environment(\.layoutDirection, ltrValue ? .leftToRight : LanguageManager.shared.layoutDirection)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            switch glyph {
            case .edit:
                Image(systemName: "pencil")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.primary.dsChrome(in: section).dsReadableGlyph)
                    .accessibilityHidden(true)
            case .menu:
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            case .open:
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            case .none:
                EmptyView()
            }
        }
        .frame(minHeight: DSBox.tileMinHeight)
        .dsRowBox()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// خيار ظاهر (خياران أو ثلاثة) — «ج» اختيار المالك ٢٠٢٦-١١-١١: كل خيار خانة بنفس مقاس خانات البيانات
/// (الميلاد والحالة) جنب بعض، المختار كحلي بنصّ أبيض والباقي رمادي الخانة بنصّ خافت. بلا إطار.
struct DSChoiceTile<ID: Hashable>: View {
    var icon: String? = nil
    let label: String
    let options: [DSChoiceOption<ID>]
    @Binding var selection: ID
    @Environment(\.dsInCenterBox) private var inBox
    @Environment(\.dsSection) private var section
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // من حجم الخط xxLarge عمود واحد — مثل شبكة الخانات (`DSTileGrid`)
        let layout = typeSize >= .xxLarge
            ? AnyLayout(VStackLayout(spacing: DSBox.tileGap))
            : AnyLayout(HStackLayout(spacing: DSBox.tileGap))
        layout {
            ForEach(options) { option in
                let on = option.id == selection
                Button {
                    withAnimation(reduceMotion ? nil : DS.Anim.snappy) { selection = option.id }
                } label: {
                    HStack(spacing: DS.Spacing.xs) {
                        if let icon = option.icon {
                            Image(systemName: icon).dsGlyph(DS.Glyph.md).accessibilityHidden(true)
                        }
                        Text(option.title)
                            .dsFieldFont(.fieldValue)
                            .fontWeight(on ? .semibold : .regular)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: DSBox.tileMinHeight)
                    .padding(.horizontal, inBox ? DSBox.fieldHorizontalPadding : DS.Spacing.smd)
                    .padding(.vertical, inBox ? DSBox.fieldVerticalPadding : DS.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(on ? DS.Color.actionNavy.dsChromeFill(in: section) : DS.Color.fieldFill)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel("\(label): \(option.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// خلية بقائمة خيارات (خياران أو أكثر): القيمة هي الحالة نفسها، والقائمة أصلية بعلامة ✓ على المختار
struct DSMenuTile<ID: Hashable>: View {
    var icon: String? = nil
    let label: String
    let options: [DSChoiceOption<ID>]
    @Binding var selection: ID
    /// ما يُعرض حين لا يطابق الاختيار أي خيار
    var placeholder: String = L10n.t("اختر", "Choose")

    var body: some View {
        let current = options.first { $0.id == selection }
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options) { option in
                    if let icon = option.icon {
                        Label(option.title, systemImage: icon).tag(option.id)
                    } else {
                        Text(option.title).tag(option.id)
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            DSFieldTileFace(icon: icon, label: label, value: current?.title ?? placeholder,
                            isPlaceholder: current == nil, glyph: .menu)
        }
        // وجه القائمة كزرّ عادي — بلا تخفيف النظام للنصّ (قيمة الخلية بلون القيم نفسه)
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(current?.title ?? placeholder)
    }
}

/// عنصر في `DSTileGrid`: `.half` قصيرة (تتجاور)، `.wide` بعرض السطر
struct DSTileItem: Identifiable {
    let id = UUID()
    let wide: Bool
    let view: AnyView
    static func half<V: View>(_ view: V) -> DSTileItem { DSTileItem(wide: false, view: AnyView(view)) }
    static func wide<V: View>(_ view: V) -> DSTileItem { DSTileItem(wide: true, view: AnyView(view)) }
}

/// شبكة خلايا البيانات: عمودان متساويان للقصيرة؛ `wide` والفردية الباقية بعرض السطر؛ عمود واحد من xxLarge
struct DSTileGrid: View {
    let items: [DSTileItem]
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ items: [DSTileItem]) { self.items = items }

    /// الصفوف: كل صفّ خلية واحدة (بعرض السطر) أو خليتان
    private var rows: [[DSTileItem]] {
        let single = typeSize >= .xxLarge
        var rows: [[DSTileItem]] = []
        var pending: DSTileItem?
        for item in items {
            if single || item.wide {
                if let p = pending { rows.append([p]); pending = nil }
                rows.append([item])
            } else if let p = pending {
                rows.append([p, item]); pending = nil
            } else {
                pending = item
            }
        }
        if let p = pending { rows.append([p]) }
        return rows
    }

    var body: some View {
        VStack(spacing: DSBox.tileGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                if row.count == 2 {
                    HStack(alignment: .top, spacing: DSBox.tileGap) {
                        row[0].view.frame(maxWidth: .infinity)
                        row[1].view.frame(maxWidth: .infinity)
                    }
                    .environment(\.dsTileHalf, true)
                } else {
                    row[0].view.frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// عنوان القسم الموحّد خارج بطاقة `DSComposerSection` (صفحات وكتل بلا بطاقة قسم) — نفس سطر عنوان أقسام
/// المربّعات: رمز خفيف بلون القسم + العنوان بخط عناوين الأقسام
struct DSBoxSectionTitle: View {
    let title: String
    let icon: String
    var tint: Color = DS.Color.primary
    var trailing: String? = nil
    @Environment(\.dsSection) private var section

    var body: some View {
        HStack(spacing: DSBox.sectionInnerSpacing) {
            DSThreadTick()
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.lg, weight: .light)
                .foregroundColor(tint.dsChrome(in: section).dsReadableGlyph)
                .frame(width: DSBox.sectionIcon, height: DSBox.sectionIcon)
                .accessibilityHidden(true)
            Text(title)
                .font(DSBox.sectionTitleFont)
                .foregroundColor(DS.Color.fieldLabel)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// قلم صفوف الحقول الموحّد (التاريخ، الهاتف، الاسم…) — قرص صغير بلون القسم ومساحة ضغط ٤٤
struct DSFieldEditGlyph: View {
    @Environment(\.dsSection) private var section

    var body: some View {
        // رمز صغير بلا قرص (طلب المالك ٢٠٢٦-١١-١٠ «خفيف») — مساحة اللمس ٤٤ كما هي
        Image(systemName: "pencil")
            .dsGlyph(DS.Glyph.sm)
            .foregroundColor(DS.Color.primary.dsChrome(in: section).dsReadableGlyph)
            .frame(width: DS.Icon.discSmall, height: DS.Icon.discSmall)
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
    }
}

/// صفّ أمر في مربّعات الأوامر (الأم، الزوجة، الزوجات، خيارات الصورة…) — صندوق صفوف الحقول + رمز + عنوان
/// (+ سطر شرح). نفس صفوف مربّع «الزوجة» في الملف (طلب المالك ٢٠٢٦-١١-١٠ «التصاميم مو موحدة»)
struct DSCommandRow: View {
    let title: String
    let icon: String
    /// سطر صغير يشرح الخيار تحت عنوانه (اختياري)
    var hint: String? = nil
    /// لون العنوان والرمز — nil = كحلي القسم؛ `DS.Color.error` لأمر الحذف
    var tint: Color? = nil
    let action: () -> Void
    @Environment(\.dsSection) private var section

    var body: some View {
        Button(action: action) {
            // صفّ أخفّ (طلب المالك ٢٠٢٦-١١-١٠): رمز صغير بلا قرص، تعبئة فاتحة، وسهم خفيف في الطرف
            HStack(spacing: DS.Spacing.sm) {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor((tint ?? DS.Color.primary.dsChrome(in: section)).dsReadableGlyph)
                    .frame(width: DS.Icon.discSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.rowTitle)
                        .foregroundColor(tint ?? DS.Color.textPrimary)
                    if let hint {
                        Text(hint)
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                            .dsNameLines()
                            .minimumScaleFactor(0.85)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                // سهم «فتح» باتجاه القراءة (قاعدة المشروع: `chevron.left` بالعربية) — كان يشير لليمين كأنه «رجوع»
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.xs)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(minHeight: DSBox.commandRowHeight)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.fieldFill.opacity(0.6)))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(hint.map { "\(title)، \($0)" } ?? title)
    }
}

// MARK: - الخيط الذهبي (قرار المالك ٢٠٢٦-١١-١١) — مجموعة واحدة `DS.Thread`

/// علامة ذهبية صغيرة قبل عنوان القسم في المربّعات
struct DSThreadTick: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Thread.tickWidth / 2, style: .continuous)
            .fill(DS.Thread.color)
            .frame(width: DS.Thread.tickWidth, height: DS.Thread.tickHeight)
            .accessibilityHidden(true)
    }
}

/// خطّ ذهبي رفيع يتلاشى عند الطرفين — أسفل رأس المربّع
struct DSThreadHairline: View {
    var body: some View {
        LinearGradient(colors: [.clear, DS.Thread.color, DS.Thread.color, .clear],
                       startPoint: .leading, endPoint: .trailing)
            .frame(height: DS.Thread.hairline)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// صفّ الهاتف الموحّد — صندوق الصفوف + رمز الهاتف + العنوان + حقل الرقم (بدل `DSFieldBox`)
struct DSPhoneFieldRow: View {
    @Binding var country: KuwaitPhone.Country
    @Binding var digits: String
    var title: String = L10n.t("رقم الهاتف", "Phone number")
    var placeholder: String = L10n.t("رقم الهاتف", "Phone number")
    var autoFocus: Bool = false

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "phone.fill").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFieldFont(.label).foregroundColor(DS.Color.tileLabel)
                DSPhoneField(country: $country, digits: $digits, placeholder: placeholder,
                             compact: true, bordered: false, autoFocus: autoFocus)
            }
        }
        .dsRowBox()
    }
}

/// «الخصوصية» = صفّ واحد (قرار المالك ٢٠٢٦-١١-١١، العيّنة «أ — صف واحد»): صفّ حقل موحّد — اسم المعلومة عنواناً والحالة
/// الحالية سطراً صغيراً تحته، وفي الطرف قائمة منسدلة: حبّة «ظاهر ▾ / مخفي ▾» تفتح الخيارين. بلا سطر سؤال ولا سطر شرح.
/// بأحجام إمكانية الوصول ينزل الاختيار تحت العنوان. `hidden` = القيمة المخزّنة («مخفي») — نفس القيم والنداءات.
struct DSVisibilityPicker: View {
    @Binding var hidden: Bool
    /// الشرح الكامل لكل حالة — يُقرأ للقارئ الصوتي (تلميحاً)، والظاهر على الشاشة `shownState` / `hiddenState`
    let shownLine: String
    let hiddenLine: String
    /// (لم يعد يُعرض — العنوان `rowTitle`) باقٍ لتوافق أماكن الاستعمال
    var question: String = ""
    var shownTitle: String = ""
    /// اسم المعلومة — عنوان الصفّ («رقم الهاتف»، «الظهور في الشجرة»…)
    var rowTitle: String = L10n.t("الظهور", "Visibility")
    var rowIcon: String = "eye.fill"
    /// المؤنّث: «ظاهرة / مخفية»
    var feminine: Bool = false
    /// سطر الحالة القصير تحت العنوان (nil = «يظهر لأفراد العائلة» / «مخفي عن أفراد العائلة» بحسب التذكير والتأنيث)
    var shownState: String? = nil
    var hiddenState: String? = nil
    /// عنوان «الخصوصية» بقفله هنا — فقط خارج أقسام `DSComposer`؛ داخلها العنوان من `DSComposerSection`
    var showsTitle: Bool = false

    /// القيمة هي الحالة نفسها («ظاهرة لأفراد العائلة» / «مخفية عن أفراد العائلة»)
    private var shownText: String {
        shownState ?? (feminine ? L10n.t("ظاهرة لأفراد العائلة", "Shown to family members")
                                : L10n.t("ظاهر لأفراد العائلة", "Shown to family members"))
    }
    private var hiddenText: String {
        hiddenState ?? (feminine ? L10n.t("مخفية عن أفراد العائلة", "Hidden from family members")
                                 : L10n.t("مخفي عن أفراد العائلة", "Hidden from family members"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if showsTitle {
                DSBoxSectionTitle(title: L10n.t("الخصوصية", "Privacy"), icon: "lock.fill")
            }
            // خلية بيانات واحدة بقائمة (قرار المالك ٢٠٢٦-١١-١١): العنوان اسم المعلومة، والقيمة هي الحالة
            // رمز الصفّ ثابت = المعلومة نفسها، والحالة في القيمة — لا يتبدّل الرمز مع الاختيار فتختلف الصفوف
            // عن بعضها (طلب المالك ٢٠٢٦-١١-١١ «ترتيب الخصوصية»)
            DSMenuTile(icon: rowIcon, label: rowTitle, options: [
                DSChoiceOption(id: false, title: shownText, icon: "eye.fill"),
                DSChoiceOption(id: true, title: hiddenText, icon: "eye.slash.fill")
            ], selection: $hidden)
            .accessibilityHint(hidden ? hiddenLine : shownLine)
        }
    }
}

// MARK: - خطوات مرقّمة (طلب المالك ٢٠٢٦-١١-١١ «من أين أُرسل الطلب»)
//
// خطوات ١ ٢ ٣ بقرص كحلي صغير وخطّ رفيع يصل بينها، وكل خطوة شريحة بيضاء برمز صغير وعنوان — بلا عناوين
// «القسم/الصفحة/الزر». الشريحة تحمل أسطراً ثانوية اختيارية (من فعل، متى، الملاحظة) فتصير بطاقة صغيرة —
// نفس المكوّن لمسار الإرسال ولسجلّ «ما تم في الطلب». داخل صندوق الحقول الرمادي (`fieldFill`).

/// خطوة واحدة: رمز SF + عنوان (+ أسطر ثانوية)
struct DSPathStep: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    var lines: [String] = []
    /// لون رمز الخطوة (قرار: أخضر/أحمر…) — nil = كحلي القسم
    var tint: Color? = nil
}

struct DSPathSteps: View {
    let steps: [DSPathStep]
    @Environment(\.dsSection) private var section

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                row(step, index: index, last: index == steps.count - 1)
            }
        }
        .padding(DSBox.fieldHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
        .accessibilityElement(children: .contain)
    }

    private func row(_ step: DSPathStep, index: Int, last: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            // القرص المرقّم والخطّ الواصل إلى التالي (يمتدّ بارتفاع الصفّ)
            VStack(spacing: 0) {
                Text(verbatim: Self.number(index + 1))
                    .dsFont(.badge)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.Icon.section, height: DS.Icon.section)
                    .background(Circle().fill(DS.Color.primaryFill.dsChromeFill(in: section)))
                    .padding(.top, (DSBox.chipHeight - DS.Icon.section) / 2)
                if !last {
                    Rectangle()
                        .fill(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                        .frame(width: DS.Border.width)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: DS.Icon.section)
            .accessibilityHidden(true)
            chip(step)
                .padding(.bottom, last ? 0 : DS.Spacing.sm)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func chip(_ step: DSPathStep) -> some View {
        let ink = (step.tint ?? DS.Color.primary).dsChrome(in: section).dsReadableGlyph
        let shape = RoundedRectangle(cornerRadius: step.lines.isEmpty ? DSBox.chipHeight / 2 : DS.Radius.md, style: .continuous)
        return VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.xs) {
                if !step.icon.isEmpty {
                    Image(dsSymbol: step.icon)
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(ink)
                        .accessibilityHidden(true)
                }
                Text(step.title)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.tileValue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(step.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DSBox.chipPadding)
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: DSBox.chipHeight)
        .background(shape.fill(DS.Color.surface))
        .accessibilityElement(children: .combine)
    }

    /// رقم الخطوة بأرقام عربية في الواجهة العربية (١ ٢ ٣) — كالتصميم المعتمد
    static func number(_ n: Int) -> String {
        guard L10n.isArabic else { return "\(n)" }
        let digits: [Character] = ["٠", "١", "٢", "٣", "٤", "٥", "٦", "٧", "٨", "٩"]
        return String(String(n).compactMap { $0.wholeNumberValue.map { digits[$0] } })
    }
}
