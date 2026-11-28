import SwiftUI

// MARK: - مربّع الطلب بالمنتصف (العيّنة `reports/app-review/inbox/inbox-box.png`، ٢٠٢٦-١١-٢٨ — «خوش تصميم نفّذه»)
//
// المختصر: رأس كحلي (رمز النوع · عنوان الطلب · النوع والوقت · ✕) ← صاحب الطلب و«عن نفسه/عن فلان»
// ← «التغيير المطلوب» قبل ← بعد (أو ملخّص الطلب حسب نوعه) ← سطر الحالة (نفس `rowState`)
// ← «رفض» (إطار أحمر) و«موافقة» (أخضر) لمن يملك القرار فقط ← «عرض التفاصيل الكاملة».
// «عرض التفاصيل الكاملة» يكبّر المربّع نفسه (`DSExpandableCenterPanel`، حركة DSMotion) ويظهر المربّع الكامل
// (المسار، السجل، الملاحظات، «المزيد»…) يتمرّر، و«إخفاء التفاصيل» يرجعه مختصراً. «تقليل الحركة» = تبديل بلا حركة.
// القطع هنا عرض فقط؛ القرار وصلاحياته في `AdminAllRequestsView`.

enum AdminRequestPanelText {
    static let showFull = L10n.t("عرض التفاصيل الكاملة", "Show full details")
    static let hideFull = L10n.t("إخفاء التفاصيل", "Hide details")
    static let change = L10n.t("التغيير المطلوب", "Requested change")
    static let summary = L10n.t("الطلب", "The request")

    /// «عن نفسه» / «عن نفسها» / «عن فلان»
    static func about(isSelf: Bool, female: Bool, subject: String?) -> String? {
        if isSelf { return female ? L10n.t("عن نفسها", "About herself") : L10n.t("عن نفسه", "About himself") }
        guard let subject, !subject.isEmpty else { return nil }
        return L10n.t("عن \(subject)", "About \(subject)")
    }
}

/// ما يعرضه المختصر — يبنيه «الوارد» من الطلب (ويُعاد استعماله في صفحة «بانتظار المراجعة»)
struct AdminRequestSummaryModel {
    var name: String
    var avatarURL: String? = nil
    /// «عن نفسه» / «عن فلان» — nil = بلا سطر
    var about: String? = nil
    /// قبل ← بعد (`AdminRequestInsights.changes`)
    var changes: [AdminRequestChange] = []
    /// ملخّص الطلب حين لا «قبل ← بعد» (`rowAsk`)
    var summary: String? = nil
    var pills: [AdminInboxRowModel.Pill] = []
    var stateWord: String? = nil
    var stateTone: AdminInboxRowModel.StateTone = .neutral
}

// MARK: - المضيف

/// المربّع بالمنتصف يتوسّع: الرأس الكحلي ثابت، وتحته المختصر أو الكامل (`full` يُبنى وهو موسّع فقط)
struct AdminRequestPanel<Compact: View, Full: View>: View {
    @Binding var expanded: Bool
    let title: String
    let subtitle: String
    let icon: String
    /// قرار يُرسل — لا يُغلق المربّع على طلب لم يُعرف مصيره
    var closeLocked: Bool = false
    let onClose: () -> Void
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let full: () -> Full

    var body: some View {
        DSExpandableCenterPanel(isExpanded: $expanded, closeLocked: closeLocked, onClose: onClose) {
            VStack(spacing: 0) {
                AdminRequestPanelHeader(title: title, subtitle: subtitle, icon: icon, closeLocked: closeLocked)
                if expanded {
                    full()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        // الموسّع بأقصى ارتفاع المربّع (٩٠٪) — والباقي يتمرّر داخله
                        .preference(key: SheetContentHeightKey.self, value: AdminRequestPanelMetrics.expandedProbe)
                } else {
                    compact()
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                }
            }
            .background(GeometryReader { geo in
                Color.clear.preference(key: DSPanelCollapsedHeightKey.self, value: expanded ? 0 : geo.size.height)
            })
        }
    }
}

enum AdminRequestPanelMetrics {
    /// قيمة أكبر من أي شاشة: الموسّع يأخذ سقف المربّع (`min(…, cap)`)
    static let expandedProbe: CGFloat = 10_000
    static let avatar: CGFloat = DS.Icon.tapTarget
    static let stateDot: CGFloat = DS.Spacing.sm
}

/// الرأس الكحلي الموحّد (`DSComposerHeader`) و✕ يغلق بحركة المربّع
private struct AdminRequestPanelHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let closeLocked: Bool
    @Environment(\.dsPanelClose) private var panelClose

    var body: some View {
        DSComposerHeader(title: title, subtitle: subtitle, icon: icon, tint: DS.Color.actionNavy,
                         onClose: { if !closeLocked { panelClose?() } })
    }
}

/// «إخفاء التفاصيل» أعلى الموسّع — يرجع المربّع مختصراً
struct AdminRequestPanelCollapseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: "chevron.up").dsGlyph(DS.Glyph.xs, weight: .semibold)
                Text(AdminRequestPanelText.hideFull)
            }
            .dsFont(.chip)
            .foregroundColor(DS.Color.info)
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - المختصر

struct AdminRequestPanelSummary: View {
    let model: AdminRequestSummaryModel
    /// «رفض» و«موافقة» (أو قرارا المسار) — فارغ لمن لا يملك القرار
    var decisions: [AdminBoxAction] = []
    var busyId: String? = nil
    var locked: Bool = false
    var notice: AdminBoxNotice? = nil
    var quietLine: String? = nil
    /// nil = بلا رابط «عرض التفاصيل الكاملة»
    var onExpand: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminRequestSummaryBody(model: model)
            if let notice { noticeLine(notice) }
            if !decisions.isEmpty { buttons }
            else if let quietLine {
                Text(quietLine)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onExpand {
                Button(action: onExpand) {
                    HStack(spacing: DS.Spacing.xs) {
                        Text(AdminRequestPanelText.showFull)
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .dsGlyph(DS.Glyph.xs, weight: .semibold)
                    }
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.info)
                    .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(locked)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.sm)
        .background(DS.Color.surface)
        .animation(DS.Anim.snappy, value: notice)
    }

    /// «رفض» (إطار أحمر، أضيق) ثم «موافقة» (أخضر، أعرض) — بالعربية «رفض» يميناً كما في العيّنة
    private var buttons: some View {
        let ordered = decisions.sorted { a, _ in a.style == .reject }
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
        return layout {
            ForEach(ordered) { action in
                Button(action: action.run) {
                    AdminBoxActionFace(title: action.title, icon: nil,
                                       style: action.style == .primary ? .approve : action.style,
                                       busy: busyId == action.id, fills: true)
                }
                .buttonStyle(DSPressStyle())
                .disabled(locked || !action.isEnabled)
                .layoutPriority(action.style == .reject ? 0 : 1)
                .frame(maxWidth: action.style == .reject && !typeSize.isAccessibilitySize && ordered.count > 1
                       ? DS.Icon.tapTarget * 3 : .infinity)
            }
        }
        .opacity(locked ? DSActionFill.disabledOpacity : 1)
    }

    private func noticeLine(_ notice: AdminBoxNotice) -> some View {
        let tint: Color = notice.kind == .error ? DS.Color.error : (notice.kind == .slow ? DS.Color.warning : DS.Color.textSecondary)
        return Text(notice.text)
            .dsFont(.subtitle)
            .foregroundColor(tint)
            .fixedSize(horizontal: false, vertical: true)
            .transition(.opacity)
    }
}

/// صاحب الطلب ← التغيير/الملخّص ← سطر الحالة — جسم المختصر، ويُعاد في بطاقات «بانتظار المراجعة»
struct AdminRequestSummaryBody: View {
    let model: AdminRequestSummaryModel
    var showsState: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            requester
            if !model.changes.isEmpty {
                AdminRequestChangeBox(changes: model.changes)
            } else if let summary = model.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(AdminRequestPanelText.summary)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                    Text(summary)
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
                .accessibilityElement(children: .combine)
            }
            if showsState, !model.pills.isEmpty || model.stateWord != nil { stateLine }
        }
    }

    private var requester: some View {
        HStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(name: model.name, avatarUrl: model.avatarURL, size: AdminRequestPanelMetrics.avatar,
                           roleColor: AppSection.admin.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(model.name)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let about = model.about {
                    Text(about)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var stateLine: some View {
        DSChipFlow(spacing: DS.Spacing.sm, lineSpacing: DS.Spacing.xs) {
            ForEach(Array(model.pills.enumerated()), id: \.offset) { _, pill in
                AdminStatePill(title: pill.title, tone: pill.tone)
            }
            if let word = model.stateWord {
                let tint = model.stateTone == .mine ? DS.Color.accent : DS.Color.textTertiary
                HStack(spacing: DS.Spacing.xs) {
                    Circle().fill(tint)
                        .frame(width: AdminRequestPanelMetrics.stateDot, height: AdminRequestPanelMetrics.stateDot)
                        .accessibilityHidden(true)
                    Text(word)
                        .dsFont(model.stateTone == .mine ? .chip : .subtitle)
                        .foregroundColor(tint)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// «التغيير المطلوب»: قبل (رمادي) ← بعد (أخضر عريض) — العنوان فوق كل صفّ حين يكون أكثر من تغيير
struct AdminRequestChangeBox: View {
    let changes: [AdminRequestChange]

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(AdminRequestPanelText.change)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    if changes.count > 1 {
                        Text(change.label)
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    HStack(spacing: DS.Spacing.sm) {
                        // بعد التنفيذ قد يساوي الحالي المطلوب (طلب مقبول) — يُعرض «بعد» وحده
                        if let current = change.current, !current.isEmpty, current != change.requested {
                            Text(current)
                                .dsFont(.body)
                                .foregroundColor(DS.Color.textTertiary)
                                .lineLimit(2)
                            Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                                .foregroundColor(DS.Color.textSecondary)
                                .accessibilityHidden(true)
                        }
                        Text(change.requested)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.success)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(change.label + ": " + (change.current ?? L10n.t("لا شيء", "nothing"))
                                    + L10n.t(" إلى ", " to ") + change.requested)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
    }
}

// MARK: - السحب على صفّ الطلب (العيّنة inbox-box، ٢٠٢٦-١١-٢٨)

/// بالعربية: «موافقة» و«رفض» على **اليسار** (تظهر بالسحب لليمين)، و«حذف» وحده على **اليمين** (بالسحب لليسار، بتأكيد).
/// `.trailing` في واجهة عربية = الحافة اليسرى، و`.leading` = اليمنى. «المزيد» ليس في السحب — مكانه في التفاصيل الكاملة.
struct RequestSwipeActions: ViewModifier {
    let enabled: Bool
    let approve: (() -> Void)?
    let approveLabel: String
    let approveIcon: String
    let approveColor: Color
    let reject: (() -> Void)?
    let delete: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // الأول عند الحافة: «موافقة» في الطرف، و«رفض» بجانب الصفّ
                    if let approve {
                        Button(action: approve) {
                            Label(approveLabel, systemImage: approveIcon)
                        }
                        .tint(approveColor)
                    }
                    if let reject {
                        Button(action: reject) {
                            Label(L10n.t("رفض", "Reject"), systemImage: "xmark")
                        }
                        .tint(DS.Color.reject)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if let delete {
                        // التأكيد قبل الحذف في «الوارد» (`swipeDeleteDetail`)
                        Button(action: delete) {
                            Label(L10n.t("حذف", "Delete"), systemImage: "trash.fill")
                        }
                        .tint(DS.Color.error)
                    }
                }
        } else {
            content
        }
    }
}
