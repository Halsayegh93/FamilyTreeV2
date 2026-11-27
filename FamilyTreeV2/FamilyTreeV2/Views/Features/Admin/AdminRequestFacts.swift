import SwiftUI

// MARK: - طلبات أوضح (§10، طلب المالك ٢٠٢٦-١١-١٣ «إضافة (قريبة) حط توضيح كامل — نوع الطلب شنو — منو مقدّم الطلب»)
//
// كل طلب يخصّ شخصاً: ثلاثة صفوف أولاً في «بيانات الطلب» — «نوع الطلب» (شريحة إضافة/حذف/تعديل/انضمام) ·
// «القرابة» (حين تُعرف: «زوجة لـ «فلان»») · «مقدّم الطلب» (الأسماء الثلاثة الأولى + «صاحب الشأن» إن كان عن نفسه،
// والضغط يفتح ملفه). البطاقات: «مقدّم الطلب: …» بشريحة النوع في أوله. نفسه في الأندرويد.

/// نوع الطلب في شريحة: إضافة (أخضر) · حذف (أحمر) · تعديل · انضمام (كحلي)
enum AdminRequestKind: Equatable {
    case add, delete, edit, join

    var title: String {
        switch self {
        case .add: return L10n.t("إضافة", "Add")
        case .delete: return L10n.t("حذف", "Delete")
        case .edit: return L10n.t("تعديل", "Edit")
        case .join: return L10n.t("انضمام", "Join")
        }
    }

    var tint: Color {
        switch self {
        case .add: return DS.Color.palm
        case .delete: return DS.Color.error
        case .edit, .join: return DS.Color.brand
        }
    }

    /// النوع من الطلب — nil = لا يخصّ شخصاً (بلاغ، رسالة)
    static func of(_ r: AdminRequest) -> AdminRequestKind? {
        switch r.requestType {
        case RequestType.relativeAdd.rawValue, RequestType.childAdd.rawValue: return .add
        case RequestType.relativeRemove.rawValue, RequestType.accountDelete.rawValue: return .delete
        case RequestType.joinRequest.rawValue, RequestType.linkRequest.rawValue: return .join
        case RequestType.treeEdit.rawValue:
            switch r.treeEditPayload?.resolvedAction {
            case .add: return .add
            case .delete: return .delete
            default: return .edit
            }
        case RequestType.nameChange.rawValue, RequestType.familyChange.rawValue, RequestType.phoneChange.rawValue,
             RequestType.photoSuggestion.rawValue, RequestType.deceasedReport.rawValue,
             RequestType.privacyRequest.rawValue:
            return .edit
        default:
            return nil
        }
    }
}

/// الصفوف الثلاثة لطلب يخصّ شخصاً
struct AdminRequestFacts {
    let kind: AdminRequestKind
    /// «زوجة لـ «مشاري ابراهيم حسن»» — nil = لا قرابة معروفة
    let relation: String?
    let requesterId: UUID?
    /// الأسماء الثلاثة الأولى (+ « · صاحب الشأن»)
    let requester: String
    /// الأسماء الثلاثة الأولى وحدها (سطر البطاقة)
    let requesterShort: String

    static func of(_ r: AdminRequest, member: (UUID) -> FamilyMember?) -> AdminRequestFacts? {
        guard let kind = AdminRequestKind.of(r) else { return nil }
        let requesterMember = member(r.requesterId) ?? (r.memberId == r.requesterId ? r.member : nil)
        let short = requesterMember?.chainThreeName ?? "—"
        // عن نفسه: المعني = مقدّم الطلب (الهدف في تعديل الشجرة، وإلا صاحب الطلب)
        let subject: UUID? = {
            switch r.requestType {
            case RequestType.treeEdit.rawValue:
                return r.treeEditPayload?.targetMemberId.flatMap(UUID.init(uuidString:)) ?? r.memberId
            case RequestType.relativeAdd.rawValue, RequestType.relativeRemove.rawValue, RequestType.childAdd.rawValue:
                return nil
            default:
                return r.memberId
            }
        }()
        let isSelf = subject == r.requesterId && r.treeEditPayload?.resolvedAction != .add
        let requester = isSelf ? short + L10n.t(" · صاحب الشأن", " · the person concerned") : short
        return AdminRequestFacts(kind: kind, relation: relation(r, requester: short, member: member),
                                 requesterId: requesterMember?.id ?? r.requesterId, requester: requester,
                                 requesterShort: short)
    }

    /// طلب تعديل بلا صفّ `AdminRequest` (تغيير الرقم)
    static func edit(requesterId: UUID, subjectId: UUID, member: (UUID) -> FamilyMember?) -> AdminRequestFacts {
        let short = member(requesterId)?.chainThreeName ?? "—"
        let requester = requesterId == subjectId ? short + L10n.t(" · صاحب الشأن", " · the person concerned") : short
        return AdminRequestFacts(kind: .edit, relation: nil, requesterId: requesterId, requester: requester,
                                 requesterShort: short)
    }

    /// «القرابة»: إضافة/حذف قريبة بنوعها، وإضافة ابن/بنت — «لـ «مقدّم الطلب»» بعدها
    private static func relation(_ r: AdminRequest, requester: String, member: (UUID) -> FamilyMember?) -> String? {
        let word: String?
        switch r.requestType {
        case RequestType.relativeAdd.rawValue:
            word = RelativeAddDetails.parse(r.details)?.relationTitle
        case RequestType.relativeRemove.rawValue:
            word = RelativeRemoveDetails.parse(r.details)?.relationTitle
        case RequestType.childAdd.rawValue:
            let child = r.newValue.flatMap(UUID.init(uuidString:)).flatMap(member)
            word = child?.isFemale == true ? L10n.t("بنت", "Daughter") : L10n.t("ابن", "Son")
        case RequestType.treeEdit.rawValue where r.treeEditPayload?.resolvedAction == .add:
            if let lines = WomenTreeRequestLines(r.treeEditPayload?.notes ?? "") {
                switch lines.relation {
                case .wife: word = L10n.t("زوجة", "Wife")
                case .mother: word = L10n.t("أم", "Mother")
                case nil: word = L10n.t("بنت", "Daughter")
                }
            } else {
                word = L10n.t("ابن", "Son")
            }
        default:
            word = nil
        }
        guard let word else { return nil }
        guard requester != "—" else { return word }
        return L10n.t("\(word) لـ «\(requester)»", "\(word) of «\(requester)»")
    }
}

/// الصفوف الثلاثة أول «بيانات الطلب» — بشكل صفوف المربّع نفسها (`dsRowBox`)
struct AdminRequestFactRows: View {
    let facts: AdminRequestFacts
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var openMember: FamilyMember? = nil

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            row(icon: "tag.fill", tint: facts.kind.tint, label: AdminRequestFactText.kind) {
                DSStatusChip(text: facts.kind.title, tint: facts.kind.tint, size: .mini)
            }
            if let relation = facts.relation {
                row(icon: "person.2.fill", tint: DS.Color.palm, label: AdminRequestFactText.relation) {
                    valueText(relation)
                }
            }
            let requester = facts.requesterId.flatMap { memberVM.member(byId: $0) }
            Button { openMember = requester } label: {
                row(icon: "person.fill", tint: AppSection.admin.ink, label: AdminRequestFactText.requester,
                    tappable: requester != nil) {
                    valueText(facts.requester)
                }
            }
            .buttonStyle(DSPressStyle())
            .disabled(requester == nil)
        }
        // بطاقة العضو «أ»: ورقة طويلة من الأسفل (اعتمدها المالك ٢٠٢٦-١١-٢٧، كانت مربّعاً بالمنتصف)
        .dsTallBox(item: $openMember) { m in
            MemberDetailsView(member: m)
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .dsFieldFont(.fieldValue)
            .foregroundColor(DS.Color.fieldValue)
            .lineLimit(2)
    }

    private func row<Value: View>(icon: String, tint: Color, label: String, tappable: Bool = false,
                                  @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: icon, tint: tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(DS.Color.fieldLabel)
                value()
            }
            Spacer(minLength: 0)
            if tappable {
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity)
        .dsRowBox()
    }
}

/// الصفوف الثلاثة داخل بطاقة «التفاصيل» في مربّع الطلب الجديد (U9، spec A.6): «نوع الطلب» بحبّة كلمة · «القرابة» ·
/// «مقدّم الطلب» ‹ — والضغط يدفع ورقة العضو داخل مكدس المربّع (`onOpenPerson`) بدل ورقة فوق ورقة
struct AdminRequestFactList: View {
    let facts: AdminRequestFacts
    /// nil = الصفّ للعرض فقط
    var onOpenPerson: ((UUID) -> Void)? = nil
    @EnvironmentObject var memberVM: MemberViewModel

    var body: some View {
        VStack(spacing: 0) {
            row(icon: "tag.fill", tint: facts.kind.tint, label: AdminRequestFactText.kind) {
                AdminStatePill(title: facts.kind.title, tone: facts.kind.pillTone).fixedSize()
            }
            if let relation = facts.relation {
                AdminRowDivider(inset: AdminRowDivider.iconInset)
                row(icon: "person.2.fill", tint: DS.Color.palm, label: AdminRequestFactText.relation) {
                    valueText(relation)
                }
            }
            AdminRowDivider(inset: AdminRowDivider.iconInset)
            let requester = facts.requesterId.flatMap { memberVM.member(byId: $0) }
            if let requester, let onOpenPerson {
                Button { onOpenPerson(requester.id) } label: {
                    row(icon: "person.fill", tint: AppSection.admin.ink, label: AdminRequestFactText.requester, chevron: true) {
                        valueText(facts.requester)
                    }
                }
                .buttonStyle(AdminRowPressStyle())
                .accessibilityHint(L10n.t("يفتح بياناته", "Opens their details"))
            } else {
                row(icon: "person.fill", tint: AppSection.admin.ink, label: AdminRequestFactText.requester) {
                    valueText(facts.requester)
                }
            }
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .dsFont(.body)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.trailing)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func row<Value: View>(icon: String, tint: Color, label: String, chevron: Bool = false,
                                  @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: icon, tint: tint, filled: true)
            Text(label)
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .layoutPriority(1)
            Spacer(minLength: DS.Spacing.sm)
            value()
            if chevron { DSChevron() }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension AdminRequestKind {
    /// نغمة الحبّة في المربّع الجديد: إضافة ✓ · حذف أحمر · تعديل/انضمام رمادي (كلمة دائماً — spec A.7)
    var pillTone: AdminPillTone {
        switch self {
        case .add: return .ok
        case .delete: return .error
        case .edit, .join: return .off
        }
    }
}

/// شريحة نوع الطلب الصغيرة (قبل العنوان في القوائم)
struct AdminRequestKindChip: View {
    let kind: AdminRequestKind

    var body: some View {
        DSStatusChip(text: kind.title, tint: kind.tint, size: .mini)
            .fixedSize()
    }
}

/// سطر البطاقة: شريحة النوع ثم «مقدّم الطلب: …»
struct AdminRequestCardLine: View {
    let kind: AdminRequestKind?
    let requester: String

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            if let kind {
                DSStatusChip(text: kind.title, tint: kind.tint, size: .mini)
            }
            Text(AdminRequestFactText.requesterLine(requester))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
        }
    }
}

enum AdminRequestFactText {
    static let kind = L10n.t("نوع الطلب", "Request type")
    static let relation = L10n.t("القرابة", "Relation")
    static let requester = L10n.t("مقدّم الطلب", "Requested by")
    /// العناوين العامة للنوع (الشرائح، «ما تم في الطلب»، الحالات الفارغة)
    static let relativeAddGeneric = L10n.t("إضافة قريبة (زوجة / أم / أخت)", "Add a relative (wife / mother / sister)")
    static let relativeRemoveGeneric = L10n.t("حذف من الشجرة (ابن / بنت / زوجة)", "Remove from the tree (son / daughter / wife)")

    static func requesterLine(_ name: String) -> String {
        L10n.t("مقدّم الطلب: \(name)", "Requested by: \(name)")
    }
}
