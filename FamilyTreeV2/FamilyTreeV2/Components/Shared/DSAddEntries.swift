import SwiftUI

// MARK: - أكثر من اسم في مربّع إضافة واحد (طلب المالك ٢٠٢٦-١٠-٢٥)
//
// «امكانية اضافة اكثر من ابنة او ابن و حتى اخت اكثر من اخت مع امكانية اختيار متوفية او متوفي في الطلبات …
// وعند اختيار اضافة ابن خلها مسمى ابن وداخل المربع في اختيار ذكر او انثى».
// قائمة الأسماء في مربّعات الإضافة بشجرة النساء، و«ابن» في «طلب تعديل» بشجرة العائلة (أبناء ذكور فقط — كل ما
// يخص الإناث في شجرة النساء): لكل اسم حقله، و(للابن في شجرة النساء) ذكر/أنثى، و«متوفّى/متوفّاة»، و(حيث يُحفظ)
// الميلاد و«متزوجة». «إضافة اسم آخر» تضيف صفّاً، وكل صفّ زائد يُحذف. المضيف يكتب أو يطلب كل اسم وحده.

/// اسم واحد في النموذج
struct DSAddEntry: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    /// "male" / "female"
    var gender: String
    var deceased = false
    var married = false
    var hasBirth = false
    var birth = Date()

    init(gender: String = "male") { self.gender = gender }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isFemale: Bool { gender == "female" }
    /// لم يُدخل فيه شيء بعد
    var isBlank: Bool { trimmedName.isEmpty && !deceased && !married && !hasBirth }
}

/// قسم الأسماء: صفّ لكل اسم بفاصل رفيع بينها، و«إضافة اسم آخر» تحتها
struct DSAddEntriesSection: View {
    @Binding var entries: [DSAddEntry]
    let title: String
    var icon: String = "person.2.fill"
    var tint: Color = DS.Color.primary
    var index: Int = 1
    /// اسم الصفّ بجنسه («ابن» / «ابنة» / «أخت») — يُرقَّم حين تتعدّد الأسماء
    let rowLabel: (DSAddEntry) -> String
    var placeholder: String = L10n.t("الاسم الأول", "First name")
    /// ذكر/أنثى لكل اسم (الابن في شجرة النساء)
    var showsGender: Bool = false
    var allowsMultiple: Bool = true
    var showsBirth: Bool = false
    /// «متزوجة» للأنثى — حيث تُكتب مباشرة
    var showsMarried: Bool = false
    /// جنس الصفّ الجديد
    var newGender: String = "male"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSComposerSection(title: title, icon: icon, tint: tint,
                          trailing: entries.count > 1 ? "\(entries.count)" : nil, index: index) {
            VStack(spacing: DS.Spacing.md) {
                ForEach(entries) { entry in
                    row(entry)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if entry.id != entries.last?.id { DSDivider() }
                }
                if allowsMultiple {
                    DSChipButton(L10n.t("إضافة اسم آخر", "Add another name"), icon: "plus",
                                 tint: tint, fillsWidth: true) { add() }
                }
            }
        }
    }

    // MARK: الصفّ

    private func row(_ entry: DSAddEntry) -> some View {
        let number = (entries.firstIndex { $0.id == entry.id } ?? 0) + 1
        let label = entries.count > 1 ? rowLabel(entry) + " \(number)" : rowLabel(entry)
        let name = Binding(get: { entries.first { $0.id == entry.id }?.name ?? "" },
                           set: { value in edit(entry.id) { $0.name = value } })
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                DSComposerField(icon: entry.isFemale ? "figure.stand.dress" : "figure.stand",
                                label: label, placeholder: placeholder, text: name,
                                tint: entry.isFemale ? DS.Color.female : DS.Color.male)
                if entries.count > 1 {
                    Button { remove(entry.id) } label: {
                        Image(systemName: "minus.circle.fill")
                            .dsGlyph(DS.Glyph.xl, weight: .regular)
                            .foregroundColor(DS.Color.error)
                            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(DSPressStyle())
                    .accessibilityLabel(L10n.t("حذف ", "Remove ") + label)
                }
            }
            // خلايا البيانات المتجاورة (`DSTileGrid`، قرار المالك ٢٠٢٦-١١-١١): الجنس والحالة والميلاد و«الحالة الاجتماعية» —
            // كل واحدة خلية بقائمة أو بقلم، ونفس القيم المحفوظة
            DSTileGrid(tiles(entry))
        }
    }

    private func tiles(_ entry: DSAddEntry) -> [DSTileItem] {
        var items: [DSTileItem] = []
        if showsGender {
            items.append(.half(DSGenderPicker(selection: field(entry.id, \.gender, default: "male"))))
        }
        items.append(.half(DSMenuTile(icon: "leaf.fill", label: L10n.t("الحالة", "Status"), options: [
            DSChoiceOption(id: false, title: L10n.t("على قيد الحياة", "Alive"), icon: "heart.fill"),
            DSChoiceOption(id: true, title: entry.isFemale ? L10n.t("متوفّاة", "Deceased") : L10n.t("متوفّى", "Deceased"),
                           icon: "leaf.fill")
        ], selection: field(entry.id, \.deceased, default: false))))
        if showsBirth { items.append(.half(birthRow(entry))) }
        if showsMarried && entry.isFemale {
            items.append(.half(DSMenuTile(icon: "heart.fill", label: L10n.t("الحالة الاجتماعية", "Marital status"), options: [
                DSChoiceOption(id: false, title: L10n.t("عزباء", "Single"), icon: "person.fill"),
                DSChoiceOption(id: true, title: L10n.t("متزوجة", "Married"), icon: "heart.fill")
            ], selection: field(entry.id, \.married, default: false))))
        }
        return items
    }

    /// ربط حقل واحد من صفّ الاسم (بالمعرّف — الصفوف تُحذف وتُضاف)
    private func field<V>(_ id: UUID, _ key: WritableKeyPath<DSAddEntry, V>, default value: V) -> Binding<V> {
        Binding(get: { entries.first { $0.id == id }?[keyPath: key] ?? value },
                set: { new in withAnimation(DS.Anim.snappy) { edit(id) { $0[keyPath: key] = new } } })
    }

    /// الميلاد (اختياري) — صفّ التاريخ الموحّد يفتح مربّع التاريخ، و«بدون تاريخ» يمسحه
    private func birthRow(_ entry: DSAddEntry) -> some View {
        let id = entry.id
        return DSDateFieldRow(icon: "calendar", title: L10n.t("تاريخ الميلاد", "Birth Date"),
                              hasDate: entry.hasBirth, dateText: Self.shortDay(entry.birth)) {
            // «بدون تاريخ» داخل المنتقي
            dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                initial: entry.hasBirth ? entry.birth : nil, allowClear: entry.hasBirth) { picked in
                edit(id) { e in
                    if let picked { e.birth = picked; e.hasBirth = true } else { e.hasBirth = false }
                }
            }
        }
    }

    /// تاريخ قصير يتّسع في البطاقة — الصيغة الموحّدة
    private static func shortDay(_ date: Date) -> String { DateHelper.displayDate(date) }

    // MARK: التعديل بالمعرّف (لا بالموضع — الصفوف تُحذف وتُضاف)

    private func edit(_ id: UUID, _ change: (inout DSAddEntry) -> Void) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[i])
    }

    private func add() {
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { entries.append(DSAddEntry(gender: newGender)) }
    }

    private func remove(_ id: UUID) {
        withAnimation(reduceMotion ? nil : DS.Anim.snappy) { entries.removeAll { $0.id == id } }
    }
}

/// «طلب» بالعدد العربي (أرقام لاتينية كبقية التطبيق): طلب · طلبين · 3 طلبات · 11 طلباً · 100 طلب
enum DSRequestCount {
    static func text(_ n: Int) -> String {
        if n == 1 { return L10n.t("طلب", "1 request") }
        if n == 2 { return L10n.t("طلبين", "2 requests") }
        switch n % 100 {
        case 3...10: return L10n.t("\(n) طلبات", "\(n) requests")
        case 11...99: return L10n.t("\(n) طلباً", "\(n) requests")
        default: return L10n.t("\(n) طلب", "\(n) requests")
        }
    }
}

/// بطاقة اختيار في صفّ الاسم — كل البطاقات بمقاس واحد (عرض متساوٍ، ارتفاع بطاقة الإجراء، زوايا واحدة، خط واحد):
/// المفعّلة ممتلئة بلونها ورمز أبيض، وغيرها تعبئة خفيفة من لونها
struct DSEntryOptionCard: View {
    let title: String
    let icon: String
    let tint: Color
    let isOn: Bool
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DSMemberKit.chipRadius, style: .continuous)
        Button(action: action) {
            VStack(spacing: DS.Spacing.xxs) {
                Image(dsSymbol: icon)
                    .dsGlyph(DS.Glyph.md)
                    .accessibilityHidden(true)
                Text(title)
                    .dsFont(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(DSBox.buttonLabelMinScale)
            }
            .foregroundColor(isOn ? DS.Color.textOnPrimary : tint.dsReadableGlyph)
            .padding(.horizontal, DS.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: DSMemberKit.chipHeight)
            .background(shape.fill(isOn ? AnyShapeStyle(tint.dsSolidFill) : AnyShapeStyle(tint.opacity(DS.Opacity.tintFillSoft))))
            .overlay(shape.strokeBorder(tint.opacity(isOn ? DS.Opacity.selectedStroke : DS.Opacity.tintStroke),
                                        lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
