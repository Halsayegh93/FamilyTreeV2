import SwiftUI

// MARK: - «طلبات معلّقة» في تفاصيل العضو — شجرة الرجال وشجرة النساء
//
// طلب المالك ٢٠٢٦-١١-٢٦: «الطلبات في تفاصيل العضو نفس وضعها القديم بس تكون ارتباط واضح بالوارد».
// البطاقة والصفوف كما كانت في `MemberDetailsView` (العنوان، الأيقونة واللون حسب الإجراء، «قيد المراجعة»).
// الجديد: لمن يقرّر طلبات الشجرة (`canModerateTree`) كل صفّ زرّ يغلق المربّع ويفتح الطلب نفسه في «الوارد»
// (`.openAdminReviewForKind` + `request_id` ← `AdminAllRequestsView(focusId:)`، وفوقه سطر «الوارد ‹ القسم ‹ النوع»)،
// وفي طرفه «في الوارد ‹» بدل «معلّق»، وتحت الصفوف سطر يقول ذلك. صاحب الطلب والمشرف يرونها كما كانت (بلا رابط).

enum MemberPendingRequestsLink {
    /// يغلق المربّع (فوق تبويب الشجرة) ثم يفتح «الوارد» على الطلب — نفس طريق «افتح الطلب» في مركز الإشعارات:
    /// التبويب أولاً (قد لا يكون مبنياً بعد)، ثم الطلب بعد أن يستمع «اليوم»
    static func open(_ request: AdminRequest, dismiss: () -> Void) {
        dismiss()
        let info: [String: Any] = ["kind": request.requestType, "request_id": request.id.uuidString]
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.boxHandoff) {
            NotificationCenter.default.post(name: .openAdminRequests, object: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                NotificationCenter.default.post(name: .openAdminReviewForKind, object: nil, userInfo: info)
            }
        }
    }
}

struct MemberPendingRequestsCard: View {
    let requests: [AdminRequest]
    /// يفتح الطلب في «الوارد» — nil = بلا رابط (صاحب الطلب أو من لا يقرّر طلبات الشجرة)
    let onOpen: ((AdminRequest) -> Void)?
    /// لون الإجراءات المحايدة (الرقم، الصورة) — لون قسم المربّع
    var ink: Color = DS.Color.primary

    var body: some View {
        if !requests.isEmpty {
            DSComposerSection(
                title: L10n.t("طلبات معلّقة", "Pending Requests"),
                icon: "clock.badge.exclamationmark.fill",
                tint: DS.Color.warning,
                trailing: "\(requests.count)"
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    ForEach(requests) { request in
                        row(request)
                    }
                    if onOpen != nil {
                        Text(L10n.t("اضغط الطلب يفتح في «الوارد» على الطلب نفسه", "Tap a request to open it in the inbox"))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ request: AdminRequest) -> some View {
        if let onOpen {
            Button { onOpen(request) } label: { rowContent(request, linked: true) }
                .buttonStyle(DSPressStyle())
                .accessibilityHint(L10n.t("يفتح الطلب في الوارد", "Opens the request in the inbox"))
        } else {
            rowContent(request, linked: false)
        }
    }

    private func rowContent(_ request: AdminRequest, linked: Bool) -> some View {
        // شجرة النساء: النوع الحقيقي (`displayAction`) كما في «الوارد»
        let action = request.treeEditPayload?.displayAction
        let icon = action?.iconName ?? "questionmark.circle"
        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: color(action))
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(L10n.t(action?.arabicLabel ?? "—", action?.englishLabel ?? "—"))
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                Text(L10n.t("قيد المراجعة", "Under review"))
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.fieldValue)
            }
            Spacer(minLength: 0)
            if linked {
                DSStatusChip(text: L10n.t("في الوارد", "In inbox"),
                             icon: L10n.isArabic ? "chevron.left" : "chevron.right",
                             tint: DS.Color.info, size: .mini)
            } else {
                DSStatusChip(text: L10n.t("معلّق", "Pending"), tint: DS.Color.warning, size: .mini)
            }
        }
        .dsRowBox()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)   // الطلب وحالته عنصراً واحداً
    }

    private func color(_ action: TreeEditAction?) -> Color {
        switch action {
        case .add: return DS.Color.palm
        case .editName: return DS.Color.info
        case .editPhone: return ink
        case .editBirth: return DS.Color.palm
        case .deceased: return DS.Color.textTertiary
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return ink
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        case .none: return DS.Color.warning
        }
    }
}
