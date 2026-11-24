import Combine
import SwiftUI
import Supabase

// MARK: - «من أين وصل» في الوارد و«تفاصيل الطلب» المطوّرة (العيّنتان المعتمدتان ١٥ و١٦، ٢٠٢٦-١١-١٧)
//
// البطاقة: مسار الطلب في شريط خفيف («شجرة النساء › فاطمة علي › ابن أو ابنة») + شارة الجهاز والنسخة («آيفون · 1.0.2 (52)»،
// والقديمة بالأحمر «قديمة») + شارة التنفيذ («يُنفَّذ تلقائياً» أخضر / «تنفيذ يدوي» كهرماني). شرائح المصدر فوق القائمة بأعدادها.
// التفاصيل: الحالة والمهلة والتنفيذ · «البيانات المطلوبة» (الحالي ← المطلوب) · «فحص تلقائي» · «المرسل» بأعداد طلباته ·
// «من أين وصل» · «سجل الطلب» · «ملاحظات الإدارة» · «طلبات مرتبطة». عرض فقط — القرار وصلاحياته في مكانها.
// المسار: `sent_from` إن سُجّل، وإلا المستنتج من نوع الطلب (`AdminTrailText.pathSteps`). الجهاز: `sent_via`.

// MARK: - التنفيذ عند القبول (القاعدة الواحدة)

/// هل يُنفّذ السيرفر الطلب عند قبوله (`decide_admin_request`)؟ — المكان الوحيد لهذه القاعدة
enum AdminRequestExecution: Equatable {
    /// القبول يكتب التغيير في الشجرة/الملف في المعاملة نفسها
    case auto
    /// القبول يغلق الطلب فقط — الإدارة تنفّذه بنفسها (الانضمام والربط، طلبات شجرة النساء القديمة…)
    case manual
    /// نُفّذ عند إرساله (الخصوصية، النسب) — القبول يغلق الطلب
    case atSend

    /// أنواع ينفّذها `decide_admin_request` كاملة
    private static let autoTypes: Set<String> = [
        "child_add", "name_change", "family_change", "phone_change", "deceased_report",
        "photo_suggestion", "content_report", "news_report",
        // إضافة قريبة وحذفها: السيرفر يعيد تشغيل الإجراء باسم صاحب الطلب عند القبول (لا عند الإرسال) — تصحيح ٢٠٢٦-١١-١٨
        "relative_add", "relative_remove",
    ]
    /// الخصوصية (الإخفاء يحدث فور الإرسال) والنسب — القبول يغلق الطلب
    private static let atSendTypes: Set<String> = ["privacy_request", "lineage_request"]
    private static let manualTypes: Set<String> = ["join_request", "link_request", "contact_message", "account_delete"]

    /// nil = نوع بلا شارة (المحتوى: أخبار، ديوانيات، مشاريع، مكتبة)
    static func of(type: String, payload: TreeEditPayload?) -> AdminRequestExecution? {
        if atSendTypes.contains(type) { return .atSend }
        if manualTypes.contains(type) { return .manual }
        if autoTypes.contains(type) { return .auto }
        guard type == "tree_edit" else { return nil }
        guard let p = payload, let action = p.resolvedAction else { return .manual }
        // شجرة النساء: المنظّم (`women`) يُنفَّذ، والقديم بلا `women` يُغلق بلا إضافة
        if p.women != nil { return .auto }
        if let notes = p.notes, WomenTreeRequestLines(notes) != nil { return .manual }
        switch action {
        case .add:
            let name = p.newMemberName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? .manual : .auto
        case .other:
            // «طلب آخر» يُطبَّق لتعديلات الملف (profile_*) فقط، وغيره يُعلِم العضو فقط
            return (p.reason ?? "").hasPrefix("profile_") ? .auto : .manual
        default:
            return .auto
        }
    }

    static func of(_ request: AdminRequest) -> AdminRequestExecution? {
        of(type: request.requestType, payload: request.treeEditPayload)
    }

    var title: String {
        switch self {
        case .auto: return L10n.t("يُنفَّذ تلقائياً", "Runs automatically")
        case .manual: return L10n.t("تنفيذ يدوي", "Manual")
        case .atSend: return L10n.t("نُفِّذ عند الإرسال", "Done when sent")
        }
    }

    var icon: String {
        switch self {
        case .auto: return "bolt.fill"
        case .manual: return "hand.raised.fill"
        case .atSend: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .auto: return DS.Color.success
        case .manual: return DS.Color.warning
        case .atSend: return DS.Color.slate
        }
    }

    /// سطر «فحص تلقائي»
    var checkText: String {
        switch self {
        case .auto: return L10n.t("سيُنفَّذ تلقائياً عند القبول", "It will be applied automatically on approval")
        case .manual: return L10n.t("لن يُنفَّذ تلقائياً — تنفّذه الإدارة بنفسها بعد القبول",
                                    "Not applied automatically — the admins carry it out after approving")
        case .atSend: return L10n.t("نُفِّذ عند إرساله — القبول يغلق الطلب فقط",
                                    "Already applied when sent — approving only closes it")
        }
    }
}

// MARK: - مصدر الطلب (شرائح الفلتر)

enum AdminRequestSourceKind: String, CaseIterable, Hashable {
    case familyTree, womenTree, profile, registration, contact, content, admin, other

    var title: String {
        switch self {
        case .familyTree: return L10n.t("شجرة العائلة", "Family tree")
        case .womenTree: return L10n.t("شجرة النساء", "Women's tree")
        case .profile: return L10n.t("الملف الشخصي", "Profile")
        case .registration: return L10n.t("التسجيل", "Sign-up")
        case .contact: return L10n.t("التواصل", "Contact")
        case .content: return L10n.t("المحتوى", "Content")
        case .admin: return L10n.t("لوحة الإدارة", "Admin panel")
        case .other: return L10n.t("أخرى", "Other")
        }
    }

    var icon: String {
        switch self {
        case .familyTree: return "tree.fill"
        case .womenTree: return "figure.stand.dress"
        case .profile: return "person.crop.circle"
        case .registration: return "person.badge.plus"
        case .contact: return "envelope.fill"
        case .content: return "newspaper.fill"
        case .admin: return "shield.lefthalf.filled"
        case .other: return "ellipsis.circle"
        }
    }

    /// من خطوات المسار (المسجّل بالعربية دائماً، والمستنتج بلغة الواجهة)
    static func of(steps: [DSPathStep]) -> AdminRequestSourceKind {
        let titles = steps.map { $0.title.trimmingCharacters(in: .whitespaces) }
        if titles.contains(where: { ["التسجيل", "Sign-up"].contains($0) }) { return .registration }
        guard let first = titles.first else { return .other }
        switch first {
        case "شجرة النساء", "Women's tree": return .womenTree
        case "الشجرة", "Tree": return .familyTree
        case "الملف الشخصي", "Profile", "الأسرة", "Family", "الإعدادات", "Settings": return .profile
        case "التواصل", "Contact": return .contact
        case "الرئيسية", "Home", "الديوانيات", "Diwaniyas", "مشاريع العائلة", "Family projects",
             "مكتبة العائلة", "Family library", "الإشعارات": return .content
        case "لوحة الإدارة": return .admin
        default: return .other
        }
    }
}

/// شريحة مصدر في فلتر «الوارد»: الكل أو مصدر بعينه
enum AdminRequestSourceFilter: Hashable {
    case all
    case kind(AdminRequestSourceKind)

    func matches(_ kind: AdminRequestSourceKind?) -> Bool {
        switch self {
        case .all: return true
        case .kind(let k): return kind == k
        }
    }

    /// الشرائح: «الكل» ثم كل مصدر فيه طلبات (والمختار ولو فرغ) — nil حين لا يوجد مصدران فأكثر
    static func options(kinds: [AdminRequestSourceKind?], selected: AdminRequestSourceFilter) -> [DSFilterOption<AdminRequestSourceFilter>]? {
        var counts: [AdminRequestSourceKind: Int] = [:]
        for k in kinds.compactMap({ $0 }) { counts[k, default: 0] += 1 }
        let shown = AdminRequestSourceKind.allCases.filter { counts[$0, default: 0] > 0 || selected == .kind($0) }
        guard shown.count >= 2 || selected != .all else { return nil }
        return [DSFilterOption(id: .all, title: L10n.t("الكل", "All"), count: kinds.count)]
            + shown.map { DSFilterOption(id: .kind($0), title: $0.title, icon: $0.icon, count: counts[$0, default: 0]) }
    }
}

// MARK: - الجهاز والنسخة

enum AdminRequestDevice {
    /// رقم بناء هذه النسخة (Info.plist)
    static let currentBuild: Int? = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap { Int($0) }

    /// نسخة قديمة: آيفون/أندرويد بلا رقم بناء (نسخ المتجر قبل تسجيله)، أو آيفون ببناء أقل من هذه النسخة
    /// (أرقام بناء الأندرويد سلسلة مستقلّة — لا تُقارن بالآيفون)
    static func isOld(_ via: RequestSentVia) -> Bool {
        let platform = via.platform?.lowercased()
        guard platform == "ios" || platform == "android" else { return false }
        guard let raw = via.appBuild?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return true }
        guard platform == "ios", let build = Int(raw), let current = currentBuild else { return false }
        return build < current
    }

    static func icon(_ via: RequestSentVia) -> String {
        switch via.platform?.lowercased() {
        case "ios": return "iphone"
        case "android": return "candybarphone"
        case "web": return "globe"
        case "server": return "server.rack"
        default: return "questionmark.circle"
        }
    }

    /// «آيفون · 1.0.2 (52)» / «آيفون · قديمة» / «الموقع»
    static func text(_ via: RequestSentVia) -> String {
        var parts = [via.platformName]
        if let v = via.appVersion?.trimmingCharacters(in: .whitespaces), !v.isEmpty {
            var version = "\u{2066}\(v)"
            if let b = via.appBuild?.trimmingCharacters(in: .whitespaces), !b.isEmpty { version += " (\(b))" }
            parts.append(version + "\u{2069}")
        }
        if isOld(via) { parts.append(L10n.t("قديمة", "Old version")) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - أصل الطلب (ما تعرضه البطاقة والتفاصيل)

struct AdminRequestOrigin {
    let steps: [DSPathStep]
    let kind: AdminRequestSourceKind
    let via: RequestSentVia?
    let execution: AdminRequestExecution?

    init(steps: [DSPathStep], via: RequestSentVia?, execution: AdminRequestExecution?) {
        self.steps = steps
        self.kind = AdminRequestSourceKind.of(steps: steps)
        self.via = via
        self.execution = execution
    }
}

/// المسار في شريط خفيف: «وصل من  شجرة النساء › فاطمة علي › ابن أو ابنة» — نصّ واحد يلتفّ داخل البطاقة
/// (سطران كحدّ أقصى ثم «…»). كان شرائح متدفّقة بسطر واحد لكل خطوة، فيخرج الاسم الطويل من حافة البطاقة
/// (بلاغ المالك ٢٠٢٦-١١-١٧ «الاسم طالع برّه»). الاسم لا يتكرّر (انظر `short`).
struct AdminRequestSourceStrip: View {
    let steps: [DSPathStep]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(L10n.t("وصل من", "Sent from"))
                .dsFont(.badge)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize()
            pathText
                .dsFont(.caption)
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("وصل من: ", "Sent from: ") + steps.map(\.title).joined(separator: "، "))
    }

    private var pathText: Text {
        let chevron = Text(Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right"))
            .font(DS.Font.icon(DS.Glyph.micro, weight: .semibold))
            .foregroundColor(DS.Color.textTertiary)
        var out = Text(verbatim: "")
        for (index, step) in steps.enumerated() {
            if index > 0 { out = out + Text(verbatim: "  ") + chevron + Text(verbatim: "  ") }
            if !step.icon.isEmpty {
                out = out + Text(Image(dsSymbol: step.icon)).font(DS.Font.icon(DS.Glyph.xs)) + Text(verbatim: " ")
            }
            out = out + Text(verbatim: Self.short(step.title))
        }
        return out
    }

    /// الاسم مكتوب في البطاقة فوقه (العضو المعني ومقدّم الطلب) — لا يتكرّر هنا (طلب المالك ٢٠٢٦-١١-١٧ «في تكرار
    /// بالأسماء»): «تفاصيل محمد اسامه…» ← «تفاصيل العضو»
    static func short(_ title: String) -> String {
        let words = title.split(separator: " ").map(String.init)
        if words.first == "تفاصيل", words.count > 1 { return L10n.t("تفاصيل العضو", "Member details") }
        return title
    }
}

/// شارتا الجهاز والتنفيذ
struct AdminRequestOriginBadges: View {
    let via: RequestSentVia?
    let execution: AdminRequestExecution?

    var body: some View {
        if via != nil || execution != nil {
            NotifFlow(spacing: DS.Spacing.xs) {
                if let via {
                    DSStatusChip(text: AdminRequestDevice.text(via), icon: AdminRequestDevice.icon(via),
                                 tint: AdminRequestDevice.isOld(via) ? DS.Color.error : DS.Color.slate, size: .mini)
                }
                if let execution {
                    DSStatusChip(text: execution.title, icon: execution.icon, tint: execution.tint, size: .mini)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// ما يُضاف لبطاقة الطلب في «الوارد»
struct AdminRequestCardOrigin: View {
    let origin: AdminRequestOrigin

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            if !origin.steps.isEmpty {
                AdminRequestSourceStrip(steps: origin.steps)
            }
            AdminRequestOriginBadges(via: origin.via, execution: origin.execution)
        }
    }
}

// MARK: - رأس التفاصيل: الحالة · المهلة · التنفيذ

enum AdminRequestStatusText {
    /// «متبقٍّ 5 ساعات» — أو «متأخر» إن تجاوز مهلته (مسار الموافقات)
    static func sla(_ flow: ApprovalSnapshot) -> (text: String, late: Bool)? {
        guard let since = flow.stageSince ?? flow.createdAt else { return nil }
        let left = flow.lateAfterHours * 3600 - Date().timeIntervalSince(since)
        guard left > 0 else { return (L10n.t("متأخر", "Late"), true) }
        let hours = Int(left / 3600)
        if hours >= 48 {
            let days = hours / 24
            return (days <= 10 ? L10n.t("متبقٍّ \(days) أيام", "\(days) days left")
                               : L10n.t("متبقٍّ \(days) يوماً", "\(days) days left"), false)
        }
        switch hours {
        case 0: return (L10n.t("متبقٍّ أقل من ساعة", "Under an hour left"), false)
        case 1: return (L10n.t("متبقٍّ ساعة", "1 hour left"), false)
        case 2: return (L10n.t("متبقٍّ ساعتان", "2 hours left"), false)
        case 3...10: return (L10n.t("متبقٍّ \(hours) ساعات", "\(hours) hours left"), false)
        default: return (L10n.t("متبقٍّ \(hours) ساعة", "\(hours) hours left"), false)
        }
    }
}

struct AdminRequestStatusStrip: View {
    /// «بانتظار القرار» — nil حين يعرض مربّع المسار مرحلته في رأسه
    let state: String?
    let sla: (text: String, late: Bool)?
    let execution: AdminRequestExecution?

    var body: some View {
        if state != nil || sla != nil || execution != nil {
            NotifFlow(spacing: DS.Spacing.xs) {
                if let state {
                    DSStatusChip(text: state, icon: "hourglass", tint: DS.Color.accent, size: .mini)
                }
                if let sla {
                    DSStatusChip(text: sla.text, icon: "timer", tint: sla.late ? DS.Color.error : DS.Color.slate, size: .mini)
                }
                if let execution {
                    DSStatusChip(text: execution.title, icon: execution.icon, tint: execution.tint, size: .mini)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - «البيانات المطلوبة» و«فحص تلقائي»

struct AdminRequestChange: Identifiable {
    let id = UUID()
    let label: String
    /// nil = لا قيمة حالية («—»)
    let current: String?
    let requested: String
}

struct AdminRequestCheck: Identifiable {
    enum Tone { case ok, warning, info }
    let id = UUID()
    let tone: Tone
    let text: String
    var detail: String? = nil
}

/// الأقسام العلوية: الحالة ← «البيانات المطلوبة» ← «فحص تلقائي»
struct AdminRequestDecisionAids: View {
    let state: String?
    let sla: (text: String, late: Bool)?
    let execution: AdminRequestExecution?
    let changes: [AdminRequestChange]
    let checks: [AdminRequestCheck]
    var index: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            AdminRequestStatusStrip(state: state, sla: sla, execution: execution)
            if !changes.isEmpty {
                DSComposerSection(title: L10n.t("البيانات المطلوبة", "Requested data"),
                                  icon: "arrow.left.arrow.right", tint: AppSection.admin.ink, index: index) {
                    VStack(spacing: 0) {
                        ForEach(Array(changes.enumerated()), id: \.element.id) { i, change in
                            if i > 0 { Divider() }
                            changeRow(change)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.smd)
                    .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
                }
            }
            if !checks.isEmpty {
                DSComposerSection(title: L10n.t("فحص تلقائي", "Automatic checks"),
                                  icon: "checklist", tint: AppSection.admin.ink, index: index + 1) {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        ForEach(checks) { checkRow($0) }
                    }
                    .padding(DS.Spacing.smd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
                }
            }
        }
    }

    private func changeRow(_ change: AdminRequestChange) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(change.label)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .frame(minWidth: DS.Icon.tapTarget + DS.Spacing.md, alignment: .leading)
            Text(change.current ?? "—")
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                .foregroundColor(DS.Color.accent)
                .accessibilityHidden(true)
            Text(change.requested)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(change.label + ": " + (change.current ?? L10n.t("لا شيء", "nothing"))
                            + L10n.t(" إلى ", " to ") + change.requested)
    }

    private func checkRow(_ check: AdminRequestCheck) -> some View {
        let icon: String
        let tint: Color
        switch check.tone {
        case .ok: icon = "checkmark.circle.fill"; tint = DS.Color.success
        case .warning: icon = "exclamationmark.triangle.fill"; tint = DS.Color.warning
        case .info: icon = "info.circle.fill"; tint = DS.Color.info
        }
        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.md)
                .foregroundColor(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(check.text)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = check.detail {
                    Text(verbatim: detail)
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - بناء البيانات المطلوبة والفحص من الطلب

enum AdminRequestInsights {
    private static func clean(_ s: String?) -> String? {
        let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private static func date(_ raw: String?) -> String? {
        clean(raw).map { DateHelper.displayDate($0) ?? $0 }
    }

    private static func phone(_ raw: String?) -> String? {
        clean(raw).map { "\u{2066}" + KuwaitPhone.display($0) + "\u{2069}" }
    }

    private static let alive = L10n.t("على قيد الحياة", "Alive")
    private static let deceased = L10n.t("متوفى", "Deceased")

    /// «الحالي ← المطلوب» لكل نوع يغيّر بيانات شخص
    static func changes(_ detail: AdminAllRequestsView.RequestDetail, men: [FamilyMember], women: [FamilyMember]) -> [AdminRequestChange] {
        func man(_ id: String?) -> FamilyMember? {
            guard let id = id.flatMap(UUID.init(uuidString:)) else { return nil }
            return men.first { $0.id == id }
        }
        let nameLabel = L10n.t("الاسم", "Name")
        let birthLabel = L10n.t("الميلاد", "Birth")
        let deathLabel = L10n.t("الوفاة", "Death")
        let stateLabel = L10n.t("الحالة", "Status")
        switch detail {
        case .treeEdit(let r, let action):
            guard let p = r.treeEditPayload else { return [] }
            if let w = p.women {
                let node = women.first { $0.id.uuidString.lowercased() == w.nodeId.lowercased() }
                    ?? men.first { $0.id.uuidString.lowercased() == w.nodeId.lowercased() }
                switch w.kind {
                case "child", "sister":
                    var rows: [AdminRequestChange] = []
                    if let n = clean(w.name) { rows.append(.init(label: nameLabel, current: nil, requested: n)) }
                    if let b = date(w.birth) { rows.append(.init(label: birthLabel, current: nil, requested: b)) }
                    rows.append(.init(label: L10n.t("الجنس", "Gender"), current: nil,
                                      requested: w.gender == "male" ? L10n.t("ذكر", "Male") : L10n.t("أنثى", "Female")))
                    if w.deceased == true {
                        rows.append(.init(label: stateLabel, current: nil, requested: date(w.death).map { deceased + " · " + $0 } ?? deceased))
                    }
                    return rows
                case "edit_name":
                    return clean(w.name).map { [.init(label: nameLabel, current: node?.firstName, requested: $0)] } ?? []
                case "edit_birth":
                    return date(w.birth).map { [.init(label: birthLabel, current: date(node?.birthDate), requested: $0)] } ?? []
                case "deceased":
                    return [.init(label: stateLabel, current: node?.isDeceased == true ? deceased : alive, requested: deceased)]
                        + (date(w.death).map { [.init(label: deathLabel, current: date(node?.deathDate), requested: $0)] } ?? [])
                case "delete":
                    return [.init(label: nameLabel, current: node?.fullName ?? node?.firstName,
                                  requested: L10n.t("حذف من شجرة النساء", "Remove from the women's tree"))]
                case "set_mother":
                    let mom = w.motherId.flatMap { id in women.first { $0.id.uuidString.lowercased() == id.lowercased() } }
                    let current = node?.motherId.flatMap { id in women.first { $0.id == id } }
                    return mom.map { [.init(label: L10n.t("الأم", "Mother"), current: current?.fullName, requested: $0.fullName)] } ?? []
                default:
                    return []
                }
            }
            let target = man(p.targetMemberId)
            switch action {
            case .add:
                var rows: [AdminRequestChange] = []
                if let n = clean(p.newMemberName) { rows.append(.init(label: nameLabel, current: nil, requested: n)) }
                if let b = date(p.newBirthDate) { rows.append(.init(label: birthLabel, current: nil, requested: b)) }
                return rows
            case .editName:
                return clean(p.newName).map { [.init(label: nameLabel, current: target?.firstName, requested: $0)] } ?? []
            case .editPhone:
                return phone(p.newPhone).map { [.init(label: L10n.t("الرقم", "Phone"), current: phone(target?.phoneNumber), requested: $0)] } ?? []
            case .editBirth:
                return date(p.newBirthDate).map { [.init(label: birthLabel, current: date(target?.birthDate), requested: $0)] } ?? []
            case .deceased:
                return [.init(label: stateLabel, current: target?.isDeceased == true ? deceased : alive, requested: deceased)]
                    + (date(p.deathDate).map { [.init(label: deathLabel, current: date(target?.deathDate), requested: $0)] } ?? [])
            case .addDeathDate:
                return date(p.deathDate).map { [.init(label: deathLabel, current: date(target?.deathDate), requested: $0)] } ?? []
            case .delete:
                return [.init(label: nameLabel, current: target?.fullName ?? clean(p.targetMemberName),
                              requested: L10n.t("حذف من الشجرة", "Remove from the tree"))]
            case .addPhoto, .other:
                return []
            }
        case .nameChange(let r):
            guard let value = clean(r.newValue) else { return [] }
            let member = r.member ?? men.first { $0.id == r.memberId }
            if r.requestType == RequestType.familyChange.rawValue {
                return [.init(label: L10n.t("العائلة", "Family"), current: clean(member?.familyName), requested: value)]
            }
            return [.init(label: nameLabel, current: member?.fullName, requested: value)]
        case .phone(let r):
            let member = r.member ?? men.first { $0.id == r.memberId }
            return phone(r.newValue).map { [.init(label: L10n.t("الرقم", "Phone"), current: phone(member?.phoneNumber), requested: $0)] } ?? []
        case .deceased(let r):
            let member = r.member ?? men.first { $0.id == r.memberId }
            return [.init(label: stateLabel, current: member?.isDeceased == true ? deceased : alive, requested: deceased)]
        case .child(let r):
            guard let child = r.newValue.flatMap(UUID.init(uuidString:)).flatMap({ id in men.first { $0.id == id } }) else { return [] }
            return [.init(label: nameLabel, current: nil, requested: child.fullName)]
                + (date(child.birthDate).map { [.init(label: birthLabel, current: nil, requested: $0)] } ?? [])
        case .join, .news, .report, .diwaniya, .project, .archive, .photo:
            return []
        }
    }

    // MARK: الفحص

    /// تطبيع الاسم الأول للمقارنة (الهمزات والتاء المربوطة والألف المقصورة)
    private static func normalized(_ name: String?) -> String {
        let first = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").first.map(String.init) ?? ""
        return first
            .replacingOccurrences(of: "[أإآ]", with: "ا", options: .regularExpression)
            .replacingOccurrences(of: "ة", with: "ه")
            .replacingOccurrences(of: "ى", with: "ي")
            .lowercased()
    }

    private static func day(_ raw: String?) -> Date? {
        guard let raw = clean(raw), raw.count >= 10 else { return nil }
        return DateHelper.parse(String(raw.prefix(10)))
    }

    /// إضافة شخص: الاسم والميلاد والإخوة (تحت نفس الأب والأم) والأم التي يُضاف تحتها (لفحص الزوج)
    private struct NewPerson {
        let name: String?
        let birth: String?
        let siblings: [FamilyMember]
        var mother: FamilyMember? = nil
    }

    private static func newPerson(_ detail: AdminAllRequestsView.RequestDetail, men: [FamilyMember], women: [FamilyMember]) -> NewPerson? {
        switch detail {
        case .treeEdit(let r, let action):
            guard let p = r.treeEditPayload else { return nil }
            if let w = p.women, w.kind == "child" || w.kind == "sister" {
                let pool = women
                guard let node = pool.first(where: { $0.id.uuidString.lowercased() == w.nodeId.lowercased() }) else { return nil }
                if w.kind == "sister" {
                    let sibs = pool.filter { $0.id == node.id || ($0.fatherId != nil && $0.fatherId == node.fatherId
                                                                   && (node.motherId == nil || $0.motherId == node.motherId)) }
                    return NewPerson(name: w.name, birth: w.birth, siblings: sibs)
                }
                if node.isFemale {
                    return NewPerson(name: w.name, birth: w.birth, siblings: pool.filter { $0.motherId == node.id }, mother: node)
                }
                return NewPerson(name: w.name, birth: w.birth, siblings: pool.filter { $0.fatherId == node.id })
            }
            guard action == .add, p.women == nil, let name = clean(p.newMemberName),
                  let parent = (p.parentMemberId ?? p.targetMemberId).flatMap(UUID.init(uuidString:)) else { return nil }
            return NewPerson(name: name, birth: p.newBirthDate, siblings: men.filter { $0.fatherId == parent })
        case .child(let r):
            guard let child = r.newValue.flatMap(UUID.init(uuidString:)).flatMap({ id in men.first { $0.id == id } }),
                  let father = child.fatherId else { return nil }
            let sibs = men.filter { $0.id != child.id && $0.fatherId == father && (child.motherId == nil || $0.motherId == child.motherId) }
            return NewPerson(name: child.firstName, birth: child.birthDate, siblings: sibs)
        default:
            return nil
        }
    }

    static func checks(_ detail: AdminAllRequestsView.RequestDetail, execution: AdminRequestExecution?,
                       men: [FamilyMember], women: [FamilyMember]) -> [AdminRequestCheck] {
        var checks: [AdminRequestCheck] = []
        if let person = newPerson(detail, men: men, women: women) {
            let key = normalized(person.name)
            if !key.isEmpty {
                if let dup = person.siblings.first(where: { normalized($0.firstName) == key }) {
                    checks.append(.init(tone: .warning,
                                        text: L10n.t("يوجد اسم مكرر «\(dup.firstName)» تحت نفس الأب والأم",
                                                     "Same name «\(dup.firstName)» already under the same parents")))
                } else {
                    checks.append(.init(tone: .ok, text: L10n.t("لا يوجد اسم مكرر تحت نفس الأب والأم",
                                                                "No duplicate name under the same parents")))
                }
            }
            if let mother = person.mother {
                checks.append(mother.husbandId != nil
                    ? .init(tone: .ok, text: L10n.t("\(mother.firstName) لها زوج في الشجرة", "\(mother.firstName) has a husband in the tree"))
                    : .init(tone: .warning, text: L10n.t("\(mother.firstName) ليس لها زوج مسجّل في الشجرة",
                                                         "\(mother.firstName) has no husband recorded in the tree")))
            }
            if let born = day(person.birth) {
                let close = person.siblings.compactMap { s -> (FamilyMember, Date)? in
                    guard normalized(s.firstName) != key, let d = day(s.birthDate) else { return nil }
                    return abs(d.timeIntervalSince(born)) < 365 * 24 * 3600 ? (s, d) : nil
                }.first
                if let close {
                    let (sibling, date) = close
                    let word = sibling.isFemale ? L10n.t("الأخت", "sister") : L10n.t("الأخ", "brother")
                    checks.append(.init(tone: .warning,
                                        text: L10n.t("فارق العمر مع \(word) \(sibling.firstName) أقل من سنة",
                                                     "Less than a year from \(word) \(sibling.firstName)"),
                                        detail: "\u{2066}\(DateHelper.format(born)) · \(DateHelper.format(date))\u{2069}"))
                }
            }
        }
        if let execution {
            checks.append(.init(tone: execution == .manual ? .warning : (execution == .auto ? .ok : .info),
                                text: execution.checkText))
        }
        return checks
    }
}

// MARK: - «المرسل»: من هو وأعداد طلباته

@MainActor
final class AdminRequesterStatsStore: ObservableObject {
    static let shared = AdminRequesterStatsStore()

    struct Stats: Equatable {
        var total = 0, approved = 0, rejected = 0, pending = 0
    }

    struct Related: Identifiable {
        let request: AdminRequest
        /// من نفس المرسل (وإلا عن نفس العضو)
        let sameSender: Bool
        var id: UUID { request.id }
    }

    @Published private(set) var stats: [UUID: Stats] = [:]
    @Published private(set) var related: [UUID: [Related]] = [:]
    private var loading: Set<UUID> = []
    private let supabase = SupabaseConfig.client
    private static let columns = "id, member_id, requester_id, request_type, status, created_at, details, new_value"

    /// يحمّل أعداد طلبات المرسل والطلبات المرتبطة بهذا الطلب (مرة لكل فتح)
    func load(requestId: UUID, requesterId: UUID, memberId: UUID?) async {
        guard !loading.contains(requestId) else { return }
        loading.insert(requestId)
        defer { loading.remove(requestId) }
        do {
            let mine: [AdminRequest] = try await supabase.from("admin_requests")
                .select(Self.columns)
                .eq("requester_id", value: requesterId.uuidString)
                .order("created_at", ascending: false)
                .limit(500)
                .execute()
                .value
            var s = Stats()
            for r in mine {
                s.total += 1
                switch r.status {
                case ApprovalStatus.approved.rawValue: s.approved += 1
                case ApprovalStatus.rejected.rawValue: s.rejected += 1
                case ApprovalStatus.pending.rawValue: s.pending += 1
                default: break
                }
            }
            stats[requesterId] = s
            var about: [AdminRequest] = []
            if let memberId, memberId != requesterId {
                about = try await supabase.from("admin_requests")
                    .select(Self.columns)
                    .eq("member_id", value: memberId.uuidString)
                    .order("created_at", ascending: false)
                    .limit(20)
                    .execute()
                    .value
            }
            var seen: Set<UUID> = [requestId]
            var list: [Related] = []
            for r in mine.prefix(20) where seen.insert(r.id).inserted { list.append(Related(request: r, sameSender: true)) }
            for r in about where seen.insert(r.id).inserted { list.append(Related(request: r, sameSender: false)) }
            related[requestId] = Array(list.sorted { ($0.request.createdAt ?? "") > ($1.request.createdAt ?? "") }.prefix(6))
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[RequestDetails] تعذّر جلب طلبات المرسل: \(error.localizedDescription)")
            }
        }
    }
}

/// ما تعرضه الأقسام السفلية عن الطلب
struct AdminRequestContext {
    let requestId: UUID?
    let sender: FamilyMember?
    /// «أمّها» / «أبوه»… حين تكون واضحة
    let relation: String?
    let memberId: UUID?
    let senderInfo: AdminSenderInfo
    /// «سجل الطلب» — nil = يعرضه مربّع المسار
    let log: [DSPathStep]?
    let viewerCanModerate: Bool
    let viewerId: UUID?
}

/// الأقسام السفلية: «المرسل» ← «من أين وصل» ← «سجل الطلب» ← (ملاحظات الإدارة) ← «طلبات مرتبطة»
struct AdminRequestContextPanel<Notes: View>: View {
    let context: AdminRequestContext
    let index: Int
    let notes: () -> Notes
    @ObservedObject private var store = AdminRequesterStatsStore.shared

    init(context: AdminRequestContext, index: Int = 3, @ViewBuilder notes: @escaping () -> Notes) {
        self.context = context
        self.index = index
        self.notes = notes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if let sender = context.sender {
                senderCard(sender)
            }
            AdminSenderSection(info: context.senderInfo, index: index + 1,
                               title: L10n.t("من أين وصل", "Where it came from"), showsSender: context.sender == nil)
            if let log = context.log, !log.isEmpty {
                DSComposerSection(title: L10n.t("سجل الطلب", "Request log"), icon: "list.number",
                                  tint: AppSection.admin.ink, index: index + 2) {
                    DSPathSteps(steps: log)
                }
            }
            notes()
            if let id = context.requestId, let items = store.related[id], !items.isEmpty {
                DSComposerSection(title: L10n.t("طلبات مرتبطة", "Related requests"), icon: "link",
                                  tint: AppSection.admin.ink, trailing: "\(items.count)", index: index + 3) {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { Divider() }
                            relatedRow(item)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.smd)
                    .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
                }
            }
        }
        .task(id: context.requestId) {
            guard let id = context.requestId, let sender = context.sender else { return }
            await store.load(requestId: id, requesterId: sender.id, memberId: context.memberId)
        }
    }

    // MARK: «المرسل»

    private func senderCard(_ sender: FamilyMember) -> some View {
        let phone = sender.dsVisiblePhone(viewerId: context.viewerId, viewerCanModerate: context.viewerCanModerate)
        let s = store.stats[sender.id]
        let since = sender.createdAt.flatMap { raw -> String? in
            raw.count >= 7 ? L10n.t("عضو منذ ", "Member since ") + "\u{2066}" + String(raw.prefix(7)) + "\u{2069}" : nil
        }
        let line = [context.relation, AdminTrailText.roleName(sender.role), since].compactMap { $0 }.joined(separator: " · ")
        return DSComposerSection(title: L10n.t("المرسل", "Sender"), icon: "person.fill",
                                 tint: AppSection.admin.ink, index: index) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(spacing: DS.Spacing.sm) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(sender.fourPartName)
                            .dsFont(.rowTitle)
                            .foregroundColor(DS.Color.textPrimary)
                            .dsNameLines()
                        if !line.isEmpty {
                            Text(line)
                                .dsFont(.caption)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                    }
                    Spacer(minLength: DS.Spacing.xs)
                    if let phone {
                        if let tel = KuwaitPhone.telURL(phone) {
                            contactButton(icon: "phone.fill", label: L10n.t("اتصال", "Call"), url: tel)
                        }
                        if let wa = KuwaitPhone.whatsappURL(phone) {
                            contactButton(icon: "message.fill", label: L10n.t("واتساب", "WhatsApp"), url: wa)
                        }
                    }
                }
                HStack(spacing: DS.Spacing.xs) {
                    statTile(s?.total, L10n.t("طلبات", "Requests"), DS.Color.textPrimary)
                    statTile(s?.approved, L10n.t("مقبولة", "Approved"), DS.Color.success)
                    statTile(s?.rejected, L10n.t("مرفوضة", "Rejected"), DS.Color.error)
                    statTile(s?.pending, L10n.t("معلّقة", "Pending"), DS.Color.warning)
                }
            }
            .padding(DS.Spacing.smd)
            .dsCard(padding: nil, radius: DS.Radius.md, fill: DS.Color.background)
        }
    }

    private func contactButton(icon: String, label: String, url: URL) -> some View {
        Button { UIApplication.shared.open(url) } label: {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.lg)
                .foregroundColor(DS.Color.sea)
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .background(Circle().fill(DS.Color.sea.opacity(DS.Opacity.tintFill)))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(label)
    }

    private func statTile(_ value: Int?, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(verbatim: value.map { "\($0)" } ?? "—")
                .dsFont(.statValue)
                .monospacedDigit()
                .foregroundColor(tint)
            Text(label)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.fieldFill))
        .accessibilityElement(children: .combine)
    }

    // MARK: «طلبات مرتبطة»

    private func relatedRow(_ item: AdminRequesterStatsStore.Related) -> some View {
        let r = item.request
        let status: (String, Color) = {
            switch r.status {
            case ApprovalStatus.approved.rawValue: return (L10n.t("مقبول", "Approved"), DS.Color.success)
            case ApprovalStatus.rejected.rawValue: return (L10n.t("مرفوض", "Rejected"), DS.Color.error)
            case ApprovalStatus.pending.rawValue: return (L10n.t("معلّق", "Pending"), DS.Color.warning)
            default: return (L10n.t("مغلق", "Closed"), DS.Color.slate)
            }
        }()
        let whose = item.sameSender ? L10n.t("من نفس المرسل", "Same sender") : L10n.t("عن نفس العضو", "About the same member")
        let when = DateHelper.displayDate(r.createdAt) ?? ""
        return HStack(spacing: DS.Spacing.sm) {
            Image(systemName: AdminTrailText.typeIcon(r))
                .dsGlyph(DS.Glyph.sm)
                .foregroundColor(DS.Color.textSecondary)
                .frame(width: DS.Icon.row)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(AdminTrailText.typeTitle(r))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text([whose, when].filter { !$0.isEmpty }.joined(separator: " · "))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            DSStatusChip(text: status.0, tint: status.1, size: .mini)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «سجل الطلب» (خارج مسار الموافقات)

enum AdminRequestLog {
    /// سجلّ السيرفر إن وُجد، وإلا «أُرسل»، ثم «بانتظار القرار» آخر خطوة
    static func steps(events: [AdminRequestEvent]?, requesterId: UUID?, createdAt: String?,
                      lookup: (UUID) -> FamilyMember?) -> [DSPathStep] {
        func by(_ id: UUID?, role: String?) -> String {
            if id == nil, role == "server" { return L10n.t("بواسطة: السيرفر", "By: server") }
            return L10n.t("بواسطة: ", "By: ") + (AdminTrailText.person(id, fallbackRole: role, lookup: lookup) ?? AdminTrailText.notRecorded)
        }
        var steps: [DSPathStep]
        if let events, !events.isEmpty {
            steps = events.map { e in
                var lines = [by(e.actorId, role: e.actorRole), DateHelper.displayDateTime(e.at) ?? AdminTrailText.notRecorded]
                if let note = e.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { lines.append(note) }
                return DSPathStep(icon: AdminTrailText.actionIcon(e.action), title: AdminTrailText.actionTitle(e.action),
                                  lines: lines, tint: AdminTrailText.actionTint(e.action))
            }
        } else {
            steps = [DSPathStep(icon: AdminTrailText.actionIcon("sent"), title: AdminTrailText.actionTitle("sent"),
                                lines: [by(requesterId, role: nil), DateHelper.displayDateTime(createdAt) ?? AdminTrailText.notRecorded])]
        }
        steps.append(DSPathStep(icon: "hourglass", title: L10n.t("بانتظار القرار", "Awaiting a decision"),
                                lines: [L10n.t("المالك أو المدير أو المختص", "The owner, an admin or the specialist")],
                                tint: DS.Color.accent))
        return steps
    }
}
