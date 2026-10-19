import SwiftUI

// MARK: - إعدادات «مسار الموافقات ٢» (طلب المالك ٢٠٢٦-١٠-١٦ مسار الموافقات ٢)
//
// قطع «إعدادات التطبيق ← الأعضاء ← طلبات المراجعة» تحت مفتاح المسار: مربّع «الردود الجاهزة» (إضافة وحذف
// للمالك، قراءة للمدير) ومبدّل الساعات الصغير للمهلة.

extension ApprovalTemplateKind {
    var title: String {
        switch self {
        case .recommend: return L10n.t("توصية", "Recommendation")
        case .reject: return L10n.t("رفض", "Rejection")
        case .info: return L10n.t("طلب معلومات", "Ask for info")
        case .returnBack: return L10n.t("إرجاع للمختص", "Return to specialist")
        case .note: return L10n.t("ملاحظة عامة", "General note")
        }
    }

    var icon: String {
        switch self {
        case .recommend: return "hand.thumbsup.fill"
        case .reject: return "xmark.circle.fill"
        case .info: return "questionmark.bubble.fill"
        case .returnBack: return "arrow.uturn.backward"
        case .note: return "text.bubble.fill"
        }
    }

    /// ألوان معانٍ ثابتة (الرفض بلون رفض الطلبات، المعلومات أزرق المراسلة)
    var tint: Color {
        switch self {
        case .recommend: return DS.Color.success
        case .reject: return DS.Color.reject
        case .info: return DS.Color.composerDiwaniya
        case .returnBack: return DS.Color.warning
        case .note: return DS.Color.info
        }
    }
}

// MARK: الردود الجاهزة

/// مربّع «الردود الجاهزة»: الردود مجمّعة بنوعها، وحذف كل رد (المالك)، و«رد جديد» بنوعه ونصه + «إضافة»
struct ApprovalTemplatesBox: View {
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    /// المالك يعدّل — المدير يتصفّح للقراءة (مثل بقية الإعدادات)
    let canEdit: Bool
    let onClose: () -> Void

    @State private var kind: ApprovalTemplateKind = .reject
    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?

    private var canAdd: Bool { canEdit && !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        DSComposer(
            title: L10n.t("الردود الجاهزة", "Ready replies"),
            subtitle: L10n.t("تظهر فوق ملاحظة القرار بحسب نوعه", "Shown above the decision note, by kind"),
            icon: "text.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إضافة", "Add"),
            actionIcon: "plus",
            showsAction: canEdit,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: canAdd,
            isBusy: busy,
            hasUnsavedChanges: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSubmit: add,
            onCancel: onClose
        ) {
            if canEdit {
                DSComposerSection(title: L10n.t("رد جديد", "New reply"), icon: "plus.bubble.fill",
                                  tint: DS.Color.actionNavy, index: 0) {
                    ChangedWordsFlow(spacing: DS.Spacing.xs) {
                        ForEach(ApprovalTemplateKind.allCases) { k in
                            DSChipButton(k.title, icon: kind == k ? "checkmark" : k.icon, tint: k.tint,
                                         isSelected: kind == k, size: .small) {
                                withAnimation(DS.Anim.snappy) { kind = k }
                            }
                            .accessibilityAddTraits(kind == k ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DSComposerField(icon: "text.bubble",
                                    label: L10n.t("نص الرد", "Reply text"),
                                    placeholder: L10n.t("مثلاً: البيانات غير مكتملة", "e.g. the details are incomplete"),
                                    text: $draft,
                                    tint: DS.Color.actionNavy,
                                    multiline: true,
                                    limit: 300)
                    if let error {
                        Text(error)
                            .dsFieldFont(.footnote)
                            .foregroundColor(DS.Color.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            let groups = ApprovalTemplateKind.allCases.map { k in (k, adminRequestVM.approvalTemplates(of: [k])) }
                .filter { !$0.1.isEmpty }
            if groups.isEmpty {
                DSEmptyView(L10n.t("لا ردود بعد", "No replies yet"),
                            message: canEdit ? L10n.t("أضف أول رد من فوق.", "Add the first one above.") : nil,
                            icon: "text.badge.plus", style: .compact)
            } else {
                ForEach(Array(groups.enumerated()), id: \.element.0) { index, group in
                    DSComposerSection(title: group.0.title, icon: group.0.icon, tint: group.0.tint,
                                      trailing: "\(group.1.count)", index: index + 1) {
                        VStack(spacing: DS.Spacing.xs) {
                            ForEach(group.1) { row($0) }
                        }
                    }
                }
            }
        }
        .task { await adminRequestVM.fetchApprovalTemplates(force: true) }
    }

    private func row(_ template: ApprovalTemplate) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(template.body)
                .dsFieldFont(.subtitle)
                .foregroundColor(DS.Color.fieldLabel)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canEdit {
                Button {
                    Task { error = await adminRequestVM.deleteApprovalTemplate(template) }
                } label: {
                    Image(systemName: "trash")
                        .dsGlyph(DS.Glyph.sm)
                        .foregroundColor(DS.Color.error)
                        .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.inline)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityLabel(L10n.t("حذف الرد", "Delete reply"))
            }
        }
        .dsRowBox()
    }

    private func add() {
        guard canAdd else { return }
        error = nil
        busy = true
        Task {
            let failure = await adminRequestVM.addApprovalTemplate(kind: kind, body: draft)
            busy = false
            if let failure {
                error = failure
            } else {
                draft = ""
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

// MARK: مبدّل الساعات الصغير

/// «− ٢٤ ساعة +» بارتفاع الشريحة الصغيرة ومساحة ضغط ٤٤ — للمهلة (تذكير/تصعيد)
struct ApprovalHoursStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let label: String
    let onChange: (Int) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dsSection) private var section

    var body: some View {
        let ink = DS.Color.primary.dsChrome(in: section).dsReadableGlyph
        HStack(spacing: DS.Spacing.xxs) {
            button("minus", enabled: value - step >= range.lowerBound) { onChange(max(range.lowerBound, value - step)) }
            Text(L10n.t("\(value) س", "\(value) h"))
                .dsFont(.chipCompact)
                .monospacedDigit()
                .foregroundColor(DS.Color.fieldLabel)
                .frame(minWidth: DS.Icon.tapTarget)
            button("plus", enabled: value + step <= range.upperBound) { onChange(min(range.upperBound, value + step)) }
        }
        .padding(.horizontal, DS.Spacing.xxs)
        .frame(minHeight: DSBox.chipHeightSmall)
        .background(Capsule().fill(ink.opacity(DS.Opacity.tintFillSoft)))
        .overlay(Capsule().strokeBorder(ink.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
        .opacity(isEnabled ? 1 : DSActionFill.disabledOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(L10n.t("\(value) ساعة", "\(value) hours"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value + step <= range.upperBound { onChange(value + step) }
            case .decrement: if value - step >= range.lowerBound { onChange(value - step) }
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let ink = DS.Color.primary.dsChrome(in: section).dsReadableGlyph
        return Button(action: action) {
            Image(systemName: symbol)
                .dsGlyph(DS.Glyph.smCompact, weight: .semibold)
                .foregroundColor(ink)
                .frame(width: DSBox.chipHeightSmall, height: DSBox.chipHeightSmall)
                .dsTapArea(width: DS.Icon.tapTarget, height: DSBox.chipHeightSmall)
        }
        .buttonStyle(DSPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : DSActionFill.disabledOpacity)
    }
}
