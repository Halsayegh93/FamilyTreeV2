import SwiftUI
import Supabase
import Combine

// MARK: - بيانات «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠ — الصفحة الأولى تجيب «وش يحتاجني الآن؟»)
//
// كل رقم هنا من بيانات محمّلة أصلاً في التطبيق (الطلبات، مسار الموافقات ٢، الرسائل، الأعضاء) أو من دوال
// قراءة موجودة على السيرفر (النشطون الآن، تقرير الموافقات، رصيد رسائل الدخول) — بلا أي دالة جديدة. ما لا
// يتوفّر لا يُرسم (لا أرقام مختلقة). مجال كل دور كما في «الوارد» (`AdminAllRequestsView.tabsForRole`).

/// عنصر ينتظر قراراً — صفّ في «يحتاج قرارك» ومصدر مهام «اليوم»
struct AdminDecisionItem: Identifiable {
    /// معرّف الصف في «الوارد» (للانضمام: معرّف العضو المعلّق)
    let id: UUID
    let typeTitle: String
    let icon: String
    let tint: Color
    let name: String
    let date: Date?
    let snapshot: ApprovalSnapshot?
    let waitingForMe: Bool
    let holderLabel: String?

    var isUrgent: Bool { snapshot?.isUrgent ?? false }
    var isLate: Bool { snapshot.map { $0.isLate || $0.isEscalated } ?? false }

    /// سطر الحالة: مرحلة المسار ومن عنده، وإلا عمر الطلب
    var subtitle: String {
        if let flow = snapshot {
            let stage: String
            switch flow.stage {
            case .review:  stage = L10n.t("مراجعة المختص", "Specialist review")
            case .info:    stage = L10n.t("بانتظار معلومات العضو", "Waiting for the member")
            case .approve: stage = L10n.t("ينتظر اعتماد المدير", "Awaiting manager approval")
            case .execute: stage = L10n.t("معتمد · للتنفيذ", "Approved · to carry out")
            }
            return [stage, holderLabel].compactMap { $0 }.joined(separator: " · ")
        }
        return AdminTodayText.since(date) ?? L10n.t("بانتظار المراجعة", "Awaiting review")
    }

    /// فعل المهمة حسب المرحلة: راجع / اعتمد / نفّذ
    var verb: String {
        switch snapshot?.stage {
        case .approve: return L10n.t("اعتمد", "Approve")
        case .execute: return L10n.t("نفّذ", "Carry out")
        default:       return L10n.t("راجع", "Review")
        }
    }

    /// ترتيب الأولوية: المستعجل ← المتأخر ← بانتظارك ← الأقدم
    var priorityRank: Int {
        if isUrgent { return 0 }
        if isLate { return 1 }
        if waitingForMe { return 2 }
        return 3
    }
}

/// أرقام رأس «اليوم» (بانتظارك · مستعجل · متأخر · رسائل) — نفس تعريف فلاتر «الوارد»
struct AdminTodayCounts: Equatable {
    var waiting = 0
    var urgent = 0
    var late = 0
    var unreadMessages = 0
    var pendingMessages = 0
    /// كل ما في «الوارد» لهذا الدور (= عدّاد «الكل» فيه)
    var inboxTotal = 0
}

/// تنبيه في بطاقة «تنبيهات» — يظهر فقط عند وجود مشكلة
struct AdminTodayAlert: Identifiable {
    enum Action {
        case sms, deaths, announce(DeathAnnouncementTarget), pushHealth, maintenance, scheduled, treeHealth
    }

    let id: String
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String?
    /// مقياس صغير تحت النص (رصيد رسائل الدخول) — nil بلا مقياس
    var meter: Double? = nil
    var buttonTitle: String? = nil
    var buttonStyle: AdminPillStyle = .soft
    var action: Action? = nil
}

/// مهمة في «مهام اليوم» (لمسة من الاتجاه «ب»): مشتقة من حالة حقيقية، وتصير «منجزة» حين يُحلّ ما خلفها اليوم
struct AdminTodayTask: Identifiable, Equatable {
    enum Target: Equatable {
        case inbox(UUID), sms, deaths, announce(UUID), messages
    }

    let id: String
    let title: String
    let detail: String?
    /// «!!» للمتأخر والمنخفض، «!!!» للمستعجل والعاجل
    let marks: Int
    let source: String
    let sourceIcon: String
    /// شارة الأولوية بجانب المصدر («متأخر يومين»، «مستعجل»)
    var flag: String? = nil
    var flagIcon: String = "clock"
    var flagTint: Color = DS.Color.error
    let target: Target

    static func == (a: AdminTodayTask, b: AdminTodayTask) -> Bool {
        a.id == b.id && a.title == b.title && a.detail == b.detail && a.marks == b.marks && a.flag == b.flag
    }
}

/// صفّ «اليوم في العائلة»
struct AdminFamilyTodayRow: Identifiable {
    enum Target { case memorial, deaths, directory }
    let id: String
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let target: Target
}

// MARK: - نصوص مشتركة

enum AdminTodayText {
    /// «صباح الخير» قبل الظهر، «مساء الخير» بعده
    static func greeting(_ date: Date = Date()) -> String {
        Calendar.current.component(.hour, from: date) < 12
            ? L10n.t("صباح الخير", "Good morning") : L10n.t("مساء الخير", "Good evening")
    }

    /// «الثلاثاء 20 أكتوبر» — ميلادي بالأرقام اللاتينية (نفس تواريخ التطبيق)
    static func dayLine(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: L10n.isArabic ? "ar_KW@numbers=latn" : "en_US")
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    /// «منذ ٣ س» / «منذ يومين» — nil بلا تاريخ
    static func since(_ date: Date?) -> String? {
        guard let date else { return nil }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 60 { return L10n.t("منذ \(max(minutes, 1)) د", "\(max(minutes, 1))m ago") }
        let hours = minutes / 60
        if hours < 24 { return L10n.t("منذ \(hours) س", "\(hours)h ago") }
        return L10n.t("منذ \(days(hours / 24))", "\(hours / 24)d ago")
    }

    /// «يوم» / «يومين» / «٣ أيام» / «١٢ يوماً»
    static func days(_ n: Int) -> String {
        switch n {
        case ...1:   return L10n.t("يوم", "1 day")
        case 2:      return L10n.t("يومين", "2 days")
        case 3...10: return L10n.t("\(n) أيام", "\(n) days")
        default:     return L10n.t("\(n) يوماً", "\(n) days")
        }
    }

    /// «متأخر يومين» — من بداية مرحلته
    static func late(_ flow: ApprovalSnapshot?) -> String {
        guard let since = flow?.stageSince ?? flow?.createdAt else { return L10n.t("متأخر", "Late") }
        let d = Int(Date().timeIntervalSince(since) / 86_400)
        if d < 1 { return L10n.t("متأخر", "Late") }
        return d == 1 ? L10n.t("متأخر يوماً", "Late 1 day") : L10n.t("متأخر \(days(d))", "Late \(days(d))")
    }
}

// MARK: - المصدر

@MainActor
enum AdminTodayFeed {

    /// مجال الدور — نفس `tabsForRole` في «الوارد»
    private struct Scope {
        let tree: Bool
        let content: Bool
        let photos: Bool
    }

    private static func scope(_ authVM: AuthViewModel, workflowOn: Bool) -> Scope {
        if authVM.isAdmin { return Scope(tree: true, content: true, photos: true) }
        if authVM.currentUser?.role == .supervisor { return Scope(tree: false, content: true, photos: true) }
        return Scope(tree: true, content: false, photos: workflowOn)
    }

    /// لقطات المسار في مجال الدور (المشرف: البلاغات، المراقب: الباقي)
    static func scopedSnapshots(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel) -> [ApprovalSnapshot] {
        let all = adminRequestVM.allApprovalSnapshots
        if authVM.isAdmin { return all }
        if authVM.currentUser?.role == .supervisor {
            return all.filter { ApprovalWorkflow.specialistRole(for: $0.requestType) == .supervisor }
        }
        return all.filter { ApprovalWorkflow.specialistRole(for: $0.requestType) == .monitor }
    }

    // MARK: يحتاج قرارك

    static func decisionItems(authVM: AuthViewModel, memberVM: MemberViewModel, newsVM: NewsViewModel,
                              adminRequestVM: AdminRequestViewModel, diwaniyaVM: DiwaniyasViewModel,
                              projectsVM: ProjectsViewModel) -> [AdminDecisionItem] {
        let flowOn = adminRequestVM.approvalsWorkflowOn
        let s = scope(authVM, workflowOn: flowOn)
        var items: [AdminDecisionItem] = []

        func item(id: UUID, _ title: String, _ icon: String, _ tint: Color, name: String, date: Date?) {
            let flow = adminRequestVM.approvalSnapshot(forRowId: id)
            items.append(AdminDecisionItem(
                id: id, typeTitle: title, icon: icon, tint: tint, name: name, date: date, snapshot: flow,
                waitingForMe: flow.map(adminRequestVM.isApprovalWaitingForMe) ?? false,
                holderLabel: flow.flatMap(adminRequestVM.approvalHolderLabel)))
        }
        /// الاسم الأول واسم الأب («عبدالله فيصل») — الصفّ سطر واحد
        func name(_ m: FamilyMember?) -> String {
            guard let m else { return L10n.t("عضو", "Member") }
            return m.fullName.split(separator: " ").prefix(2).joined(separator: " ")
        }
        let date = ApprovalWorkflow.date

        if s.tree {
            for m in memberVM.allMembers where m.role == .pending {
                item(id: m.id, L10n.t("انضمام", "Join"), "person.badge.plus", DS.Color.info,
                     name: name(m), date: date(m.createdAt))
            }
            for r in adminRequestVM.treeEditRequests {
                let action = r.treeEditPayload?.resolvedAction ?? .other
                item(id: r.id, L10n.t("الشجرة · \(action.arabicLabel)", "Tree · \(action.englishLabel)"),
                     action.iconName, DS.Color.palm, name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.deceasedRequests {
                item(id: r.id, L10n.t("تسجيل وفاة", "Death report"), NewsTypeHelper.icon(for: "وفاة"),
                     DS.Color.slate, name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.childAddRequests {
                item(id: r.id, L10n.t("إضافة ابن", "Add child"), "person.badge.plus", DS.Color.info,
                     name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.phoneChangeRequests {
                item(id: r.id, L10n.t("تعديل رقم", "Phone change"), "phone.fill", DS.Color.palm,
                     name: name(r.member), date: date(r.createdAt))
            }
            for r in adminRequestVM.nameChangeRequests {
                let family = r.requestType == RequestType.familyChange.rawValue
                item(id: r.id, family ? L10n.t("تغيير العائلة", "Family change") : L10n.t("تغيير اسم", "Name change"),
                     "character.cursor.ibeam", DS.Color.info, name: name(r.member), date: date(r.createdAt))
            }
        }
        if s.photos {
            for r in adminRequestVM.photoSuggestionRequests {
                item(id: r.id, L10n.t("اقتراح صورة", "Photo suggestion"), "photo.fill", DS.Color.sadu,
                     name: name(r.member), date: date(r.createdAt))
            }
        }
        if s.content {
            for r in adminRequestVM.newsReportRequests {
                item(id: r.id, L10n.t("بلاغ", "Report"), "exclamationmark.bubble.fill", DS.Color.error,
                     name: name(r.member), date: date(r.createdAt))
            }
            for p in newsVM.pendingNewsRequests {
                let preview = p.content.trimmingCharacters(in: .whitespacesAndNewlines)
                item(id: p.id, L10n.t("خبر", "News"), "newspaper.fill", DS.Color.accent,
                     name: preview.isEmpty ? p.author_name : String(preview.prefix(40)), date: p.timestamp)
            }
            for d in diwaniyaVM.pendingDiwaniyas {
                item(id: d.id, L10n.t("ديوانية", "Diwaniya"), "tent.fill", DS.Color.palm, name: d.title, date: nil)
            }
            for p in projectsVM.pendingProjects {
                item(id: p.id, L10n.t("مشروع", "Project"), "briefcase.fill", DS.Color.accent,
                     name: p.title, date: date(p.createdAt))
            }
        }

        return items.sorted { a, b in
            if a.priorityRank != b.priorityRank { return a.priorityRank < b.priorityRank }
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
    }

    // MARK: الأرقام

    static func counts(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel,
                       items: [AdminDecisionItem], inboxTotal: Int) -> AdminTodayCounts {
        var c = AdminTodayCounts()
        c.unreadMessages = adminRequestVM.unreadContactMessagesCount
        c.pendingMessages = adminRequestVM.pendingContactMessagesCount
        c.inboxTotal = inboxTotal
        if adminRequestVM.approvalsWorkflowOn {
            let flows = scopedSnapshots(authVM: authVM, adminRequestVM: adminRequestVM)
            c.waiting = flows.filter(adminRequestVM.isApprovalWaitingForMe).count
            c.urgent = flows.filter(\.isUrgent).count
            c.late = flows.filter { $0.isLate || $0.isEscalated }.count
        } else {
            // المسار مطفأ: كل طلب في مجالك بانتظارك (بلا مستعجل ولا متأخر)
            c.waiting = items.count
        }
        return c
    }

    // MARK: مهام اليوم

    static func tasks(authVM: AuthViewModel, adminRequestVM: AdminRequestViewModel, items: [AdminDecisionItem],
                      sms: SmsBalanceStore, unannounced: [FamilyMember]) -> [AdminTodayTask] {
        var tasks: [AdminTodayTask] = []

        // رصيد رسائل الدخول (المالك والمدير)
        if authVM.canViewSystemSettings, let balance = sms.status?.balance, sms.needsTopUp {
            let urgent = sms.level == .urgent
            tasks.append(AdminTodayTask(
                id: "sms-balance",
                title: L10n.t("اشحن رصيد رسائل الدخول", "Top up the sign-in SMS balance"),
                detail: L10n.t("بقي \(SmsBalanceText.points(balance)) نقطة · \(SmsBalanceText.enough(balance))",
                               "\(SmsBalanceText.points(balance)) points left · \(SmsBalanceText.enough(balance))"),
                marks: urgent ? 3 : 2,
                source: AdminArea.access.title, sourceIcon: "lock.shield.fill",
                target: .sms))
        }

        // ما ينتظر قرارك: بانتظارك أولاً (والمسار مطفأ: كل طلبات مجالك)
        let flowOn = adminRequestVM.approvalsWorkflowOn
        for item in items where (flowOn ? (item.waitingForMe || (item.snapshot == nil && authVM.isAdmin)) : true) {
            var task = AdminTodayTask(
                id: "req-\(item.id.uuidString)",
                title: "\(item.verb) \(item.typeTitle) · \(item.name)",
                detail: item.subtitle,
                marks: item.isUrgent ? 3 : item.isLate ? 2 : 0,
                source: AdminArea.inbox.title, sourceIcon: "tray.fill",
                target: .inbox(item.id))
            if item.isUrgent {
                task.flag = L10n.t("مستعجل", "Urgent")
                task.flagIcon = "flame"
                task.flagTint = DS.Color.error
            } else if item.isLate {
                task.flag = AdminTodayText.late(item.snapshot)
                task.flagTint = DS.Color.error
            }
            tasks.append(task)
        }

        // وفاة لم يُعلن عنها (المالك والمدير)
        if authVM.isAdmin {
            for m in unannounced {
                tasks.append(AdminTodayTask(
                    id: "death-\(m.id.uuidString)",
                    title: L10n.t("أعلن وفاة \(m.shortFullName)", "Announce \(m.shortFullName)'s death"),
                    detail: L10n.t("سُجّلت وفاته ولم يُعلن عنها", "Recorded but not announced"),
                    marks: 0, source: AdminArea.occasions.title, sourceIcon: "calendar.badge.clock",
                    target: .announce(m.id)))
            }
        }

        // رسائل لم يُتعامل معها
        let pending = adminRequestVM.contactMessages
            .filter { $0.status == ApprovalStatus.pending.rawValue }
            .sorted { ($0.createdAt ?? "") < ($1.createdAt ?? "") }
        for msg in pending {
            let category = ContactCategoryInfo.from(raw: ContactParser.category(of: msg)).title
            tasks.append(AdminTodayTask(
                id: "msg-\(msg.id.uuidString)",
                title: L10n.t("رُدّ على رسالة \(msg.member?.shortFullName ?? "عضو")",
                              "Reply to \(msg.member?.shortFullName ?? "a member")"),
                detail: [category, AdminTodayText.since(ContactParser.date(msg.createdAt))]
                    .compactMap { $0 }.joined(separator: " · "),
                marks: 0, source: L10n.t("الرسائل", "Messages"), sourceIcon: "bubble.left.fill",
                target: .messages))
        }
        return tasks
    }
}

// MARK: - ذاكرة مهام اليوم

/// ما ظهر من مهام اليوم — المهمة التي ظهرت اليوم ثم اختفى ما خلفها (حُلّ الطلب، شُحن الرصيد، أُعلنت الوفاة)
/// تُعرض «منجزة». لا تأشير يدوي: الدائرة حالة فقط. تُنسى مع بداية يوم جديد (مفتاح باليوم والمستخدم).
@MainActor
final class AdminTodayTaskStore: ObservableObject {
    struct Record: Codable, Identifiable, Equatable {
        let id: String
        var title: String
        var source: String
        var sourceIcon: String
        var doneAt: Date?
    }

    @Published private(set) var done: [Record] = []
    private var records: [String: Record] = [:]
    private var key = ""

    private static func dayKey(user: UUID?, role: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "adminTodayTasks.\(user?.uuidString ?? "-").\(role).\(f.string(from: Date()))"
    }

    /// يُستدعى بعد اكتمال تحميل البيانات فقط — قبله تبدو كل المهام «محلولة»
    func sync(open: [AdminTodayTask], user: UUID?, role: String) {
        let k = Self.dayKey(user: user, role: role)
        if k != key {
            key = k
            if let data = UserDefaults.standard.data(forKey: k),
               let saved = try? JSONDecoder().decode([String: Record].self, from: data) {
                records = saved
            } else {
                records = [:]
            }
        }
        let openIds = Set(open.map(\.id))
        for task in open {
            records[task.id] = Record(id: task.id, title: task.title, source: task.source,
                                      sourceIcon: task.sourceIcon, doneAt: nil)
        }
        for (id, rec) in records where rec.doneAt == nil && !openIds.contains(id) {
            records[id]?.doneAt = Date()
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: k)
        }
        let list = records.values.filter { $0.doneAt != nil }.sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        if list != done { done = list }
    }
}

// MARK: - قراءات إضافية من دوال موجودة (لا شيء جديد على السيرفر)

enum AdminTodayFetch {
    /// الوفيات المعلن عنها — nil إن تعذّر الجلب (فلا يظهر تنبيه «لم يُعلن عنها» خطأً)
    static func announcedDeathIds() async -> Set<UUID>? {
        struct Row: Decodable { let member_id: UUID }
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("death_announcements").select("member_id").execute().value
            return Set(rows.map(\.member_id))
        } catch {
            return nil
        }
    }

    /// عدد من يستخدم التطبيق الآن (`get_active_members_now` — المالك والمدير)
    static func activeNowCount() async -> Int? {
        struct Row: Decodable { let member_id: UUID }
        do {
            let response = try await SupabaseConfig.client.rpc("get_active_members_now").execute()
            let rows = try JSONDecoder().decode([Row].self, from: response.data)
            return Set(rows.map(\.member_id)).count
        } catch {
            return nil
        }
    }

    /// رموز الإشعارات الأقدم من ٣٠ يوماً (نفس تعريف «وصول الإشعارات») — المالك والمدير
    static func staleTokenCount() async -> Int? {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) else { return nil }
        let iso = ISO8601DateFormatter().string(from: cutoff)
        do {
            let response = try await SupabaseConfig.client
                .from("device_tokens")
                .select("member_id", head: true, count: .exact)
                .or("updated_at.is.null,updated_at.lt.\(iso)")
                .execute()
            return response.count
        } catch {
            return nil
        }
    }

    /// المنجز هذا الأسبوع من «تقرير الموافقات» (نُفّذ + رُفض خلال ٧ أيام) — nil إن لم يتوفّر
    static func weeklyDone() async -> (executed: Int, rejected: Int)? {
        nonisolated struct Params: Encodable { let p_from: String; let p_to: String }
        let to = Date()
        guard let from = Calendar.current.date(byAdding: .day, value: -7, to: to) else { return nil }
        let iso = ISO8601DateFormatter()
        do {
            let report: ApprovalsReport = try await SupabaseConfig.client
                .rpc("approvals_report", params: Params(p_from: iso.string(from: from), p_to: iso.string(from: to)))
                .execute().value
            return (report.totals.executed, report.totals.rejected)
        } catch {
            return nil
        }
    }
}
