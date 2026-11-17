import SwiftUI

// MARK: - «الطلبات» في شجرة النساء — الشكل «أ» (قرار المالك ٢٠٢٦-١١-١٧)
//
// قسم واحد بتسع خانات دائرية خفيفة: أبناء · الزوج · أم · أخت · تعديل اسم · تعديل ميلاد · تسجيل وفاة · طلب آخر · حذف.
// الألوان: الإضافة أخضر، تعديل البيانات كحلي، الوفاة رمادي، الحذف أحمر — ونقطة ذهبية على الطلبات الجديدة.
// ثلاث في السطر، والسطر الأخير الناقص في الوسط (لا خانة يتيمة على الطرف). بلا «إضافة صورة» (لا صور للإناث).

/// طلبات تعديل البيانات الجديدة — كلها تصل للإدارة طلباً يدوياً (`other`) لا يُنفَّذ تلقائياً عند القبول
enum WomanEditRequest: String, Identifiable {
    case editName, editBirth, deceased, other, delete
    var id: String { rawValue }

    var title: String {
        switch self {
        case .editName: return L10n.t("تعديل اسم", "Edit name")
        case .editBirth: return L10n.t("تعديل ميلاد", "Edit birth")
        case .deceased: return L10n.t("تسجيل وفاة", "Record death")
        case .other: return L10n.t("طلب آخر", "Other request")
        case .delete: return L10n.t("حذف", "Delete")
        }
    }
    /// عنوان مربّع الطلب وسطره في «الوارد» (بالعربية دائماً — بيانات تقرؤها الإدارة)
    var sourceTitle: String {
        switch self {
        case .editName: return "طلب تعديل اسم"
        case .editBirth: return "طلب تعديل تاريخ الميلاد"
        case .deceased: return "طلب تسجيل وفاة"
        case .other: return "طلب آخر"
        case .delete: return "طلب حذف"
        }
    }
    var boxTitle: String {
        switch self {
        case .editName: return L10n.t("طلب تعديل اسم", "Request a name change")
        case .editBirth: return L10n.t("طلب تعديل تاريخ الميلاد", "Request a birth date change")
        case .deceased: return L10n.t("طلب تسجيل وفاة", "Request recording a death")
        case .other: return L10n.t("طلب آخر", "Other request")
        case .delete: return L10n.t("طلب حذف", "Request deletion")
        }
    }
    var icon: String {
        switch self {
        case .editName: return "character.cursor.ibeam"
        case .editBirth: return "calendar"
        case .deceased: return "leaf.fill"
        case .other: return "ellipsis.bubble.fill"
        case .delete: return "trash.fill"
        }
    }
}

/// لون الخانة الدائرية حسب نوعها
enum WomenRequestTint {
    case add, edit, death, delete
    var color: Color {
        switch self {
        case .add: return DSMemberKit.addTint
        case .edit: return DS.Color.actionNavy
        case .death: return DS.Color.textSecondary
        case .delete: return DS.Color.error
        }
    }
}

/// خانة دائرية خفيفة: دائرة بلون خفيف وأيقونة بلونها، والاسم تحتها — ونقطة ذهبية للجديد
struct WomenRequestCircle: View {
    let title: String
    let icon: String
    let tint: WomenRequestTint
    var isNew: Bool = false
    var hint: String? = nil
    let action: () -> Void

    // مقاسات نظام التصميم الموحّد: الدائرة بمقاس الزر العائم، والرمز `DS.Glyph.xxl`
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = DS.Icon.floatingButton

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Spacing.xs) {
                ZStack {
                    Circle().fill(tint.color.opacity(DS.Opacity.tintFill))
                    Circle().strokeBorder(tint.color.opacity(DS.Opacity.fieldStroke), lineWidth: DS.Border.width)
                    Image(systemName: icon)
                        .dsGlyph(DS.Glyph.xxl, weight: .semibold)
                        .foregroundStyle(tint.color)
                }
                .frame(width: circle, height: circle)
                .overlay(alignment: .topTrailing) {
                    if isNew {
                        Circle().fill(DS.Color.goldDot)
                            .frame(width: DS.Icon.onlineDot, height: DS.Icon.onlineDot)
                            .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: DS.Border.widthBold))
                            .offset(x: -DS.Spacing.xxs, y: DS.Spacing.xxs)
                            .accessibilityHidden(true)
                    }
                }
                Text(title)
                    .dsFont(.chip)
                    .foregroundStyle(tint == .delete ? DS.Color.error : DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(hint ?? "")
    }
}

/// شبكة الخانات: ثلاث في السطر، والسطر الأخير الناقص في الوسط
struct WomenRequestCircleGrid: Layout {
    var columns: Int = 3
    var spacing: CGFloat = DS.Spacing.sm

    private func cellWidth(_ width: CGFloat) -> CGFloat {
        max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let w = cellWidth(width)
        var height: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let row = subviews[start..<min(start + columns, subviews.count)]
            let h = row.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
            height += h + (start == 0 ? 0 : spacing)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = cellWidth(bounds.width)
        var y = bounds.minY
        for start in stride(from: 0, to: subviews.count, by: columns) {
            let row = Array(subviews[start..<min(start + columns, subviews.count)])
            let h = row.map { $0.sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
            let rowWidth = CGFloat(row.count) * w + CGFloat(row.count - 1) * spacing
            // RTL/LTR: الشبكة في الوسط فالسطر الناقص متوسّط في الاتجاهين
            var x = bounds.minX + (bounds.width - rowWidth) / 2
            for view in row {
                view.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                           proposal: ProposedViewSize(width: w, height: h))
                x += w + spacing
            }
            y += h + spacing
        }
    }
}

/// مربّع طلب تعديل واحد — الحقل حسب النوع، ثم ملاحظة اختيارية؛ يُرسل أسطر الطلب للإدارة
struct WomanEditRequestBox: View {
    let kind: WomanEditRequest
    let womanName: String
    let currentFirstName: String
    let isBusy: Bool
    let onSend: (_ lines: [String]) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @State private var date = Date()
    @State private var hasDate = false
    @State private var notes = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedNotes: String { notes.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        switch kind {
        case .editName, .other: return !trimmed.isEmpty
        case .editBirth: return hasDate
        case .deceased, .delete: return true
        }
    }

    private var tint: Color {
        switch kind {
        case .deceased: return DS.Color.textSecondary
        case .delete: return DS.Color.error
        default: return DS.Color.actionNavy
        }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var body: some View {
        DSComposer(
            title: kind.boxTitle,
            subtitle: womanName,
            icon: kind.icon,
            tint: tint,
            actionTitle: L10n.t("إرسال الطلب", "Send request"),
            actionIcon: "paperplane.fill",
            canSubmit: canSend,
            isBusy: isBusy,
            note: L10n.t("يُرسل للإدارة للمراجعة", "Sent to the administration for review"),
            hasUnsavedChanges: !trimmed.isEmpty || !trimmedNotes.isEmpty || hasDate,
            onSubmit: { if canSend { onSend(lines) } },
            onCancel: onCancel
        ) {
            DSComposerSection(title: kind.title, icon: kind.icon, tint: tint, index: 0) {
                switch kind {
                case .editName:
                    DSComposerField(icon: "person.fill", label: L10n.t("الاسم الصحيح", "Correct name"),
                                    placeholder: currentFirstName.isEmpty
                                        ? L10n.t("الاسم كما يجب أن يظهر", "The name as it should appear")
                                        : L10n.t("الاسم الحالي: ", "Current: ") + currentFirstName,
                                    text: $text)
                case .editBirth:
                    dateRow(L10n.t("تاريخ الميلاد الصحيح", "Correct birth date"))
                case .deceased:
                    dateRow(L10n.t("تاريخ الوفاة (إن عُرف)", "Date of death (if known)"))
                case .other:
                    DSComposerField(icon: "text.bubble.fill", label: L10n.t("الطلب", "Request"),
                                    placeholder: L10n.t("اكتب ما تريد تعديله", "Describe the change"),
                                    text: $text, multiline: true)
                case .delete:
                    Text(L10n.t("تراجع الإدارة الطلب قبل الحذف.", "The administration reviews it before deleting."))
                        .dsFont(.footnote)
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if kind != .other {
                    DSComposerField(icon: "note.text",
                                    label: kind == .delete ? L10n.t("السبب", "Reason") : L10n.t("ملاحظات", "Notes"),
                                    placeholder: L10n.t("اختياري", "Optional"),
                                    text: $notes, multiline: true)
                }
            }
        }
    }

    @ViewBuilder
    private func dateRow(_ label: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Toggle(isOn: $hasDate.animation()) {
                Text(label).dsFont(.rowTitle).foregroundStyle(DS.Color.textPrimary)
            }
            .tint(DS.Color.actionNavy)
            if hasDate {
                DatePicker(L10n.t("التاريخ", "Date"), selection: $date, in: ...Date(), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
            }
        }
    }

    /// أسطر الطلب كما تقرؤها الإدارة في «الوارد»
    private var lines: [String] {
        var out: [String] = []
        let day = hasDate ? Self.dayFormatter.string(from: date) : nil
        switch kind {
        case .editName:
            if !currentFirstName.isEmpty { out.append("الاسم الحالي: " + currentFirstName) }
            out.append("الاسم الصحيح: " + trimmed)
        case .editBirth:
            if let day { out.append("تاريخ الميلاد الصحيح: " + day) }
        case .deceased:
            out.append("تاريخ الوفاة: " + (day ?? "غير معروف"))
        case .other:
            out.append("الطلب: " + trimmed)
        case .delete:
            out.append("المطلوب: حذف السجل من شجرة النساء")
        }
        if !trimmedNotes.isEmpty {
            out.append((kind == .delete ? "السبب: " : "ملاحظات: ") + trimmedNotes)
        }
        return out
    }
}
