import Foundation
#if !ADMIN_LOGIC_TEST
import SwiftUI
#endif

// MARK: - «الفريق والصلاحيات» (كان «الفريق والأمان» — إعادة التصميم ٢٠٢٦-١١-٢٦ spec C.13 الوحدة U16، ثم ترتيب المالك
// ٢٠٢٦-١١-٢٨: «الفريق» ← «الأعضاء»؛ رسائل رمز الدخول والأجهزة إلى «التطبيق والنظام ← النظام»، و«الاستخدام» إلى
// «الإحصاءات ← في التطبيق». البطاقات أدناه نفسها؛ `AdminAccessStatusSection` يرسم بطاقة الحال في البيتين)
//
// الرأس الكحلي («‹ الإدارة» · «الفريق والأمان ⌄» · «من يدير، ومن يدخل التطبيق»، وسطر «للاطلاع» للمدير) ثم ثلاث بطاقات:
//  ١) بطاقة الحالة «الدخول والأمان» (المالك — `team.sms`/`team.registration`/`team.devices`): بدل الحلقات الثلاث ومربّعات
//     «الدخول والأمان» التي كانت تفتح الصفحات نفسها. رأسها حبّة كلمة («سليم ✓» أو «شيئان يحتاجانك»، و«تعذّر التحميل ↻»
//     حين لم يصل مخزن)، وتحته صفّ لكل بيت: رسائل رمز الدخول · محاولات دخول مريبة (حين توجد) · التسجيل والمنع · الأجهزة
//     والإشعارات — كل صفّ يقول حاله بكلمة ويفتح بيته.
//  ٢) «فريق الإدارة» (`team.members`؛ المالك يعدّل، المدير يقرأ): «7 في الإدارة» وعدد كل دور — البطاقة كلها باب واحد إلى
//     `AdminModeratorsView` (الإضافة وتغيير الدور والإزالة و«صلاحيات الأدوار» هناك).
//  ٣) «الاستخدام» (`team.usage`): النشطون من أصحاب الحسابات + شريط ٣ أجزاء (نشط · خامل · دخل بلا جهاز) + «تفاصيل الاستخدام»
//     ← `AdminActiveMembersView`.
// كل كلمة حال من مخزنها (`AdminStoreHealth`): لا «سليم» قبل وصول البيانات، والفشل «تعذّر التحميل» لا كلمة هادئة (spec T1).
// الكتابة الوحيدة في القسم داخل صفحاته (المنع، مفتاح التسجيل — AdminRegistrationBansView.swift).
//
// الجزء الأول منطق خالص (Foundation) يُفحص بلا محاكي:
//   xcrun swiftc -D ADMIN_LOGIC_TEST -o /tmp/u16-logic FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminContracts.swift \
//     FamilyTreeV2/FamilyTreeV2/Views/Features/Admin/AdminTeamArea.swift tests/admin-redesign/U16/main.swift && /tmp/u16-logic

// MARK: - المنطق الخالص

nonisolated enum AdminTeamLogic {
    /// نغمة الحبّة (تُترجم إلى `AdminPillTone` في الواجهة)
    enum Tone: Hashable { case ok, off, warn, error }

    /// كلمة حبّة: النص والنغمة والرمز
    struct Word: Hashable {
        var text: String
        var tone: Tone
        var icon: String? = nil
    }

    /// مستوى رصيد رسائل الدخول (نفس `SmsBalanceStore.Level`)
    enum SmsLevel: Hashable { case unknown, good, low, urgent }

    /// ما تقرؤه بطاقة الحالة — كل رقم بحال مخزنه
    struct Facts {
        var seesSms = true
        var seesRegistration = true
        var seesDevices = true
        // رسائل رمز الدخول (`SmsBalanceStore`)
        var sms: AdminStoreHealth = .idle
        var smsLevel: SmsLevel = .unknown
        var balance: Double? = nil
        var daysLeft: Int? = nil
        /// «محاولات دخول مريبة» لم تُقرأ (`sms_suspicious` في إشعارات الإدارة)
        var suspicious = 0
        // التسجيل والمنع (`app_settings.allow_new_registrations` + `banned_phones`)
        var settings: AdminStoreHealth = .idle
        var registrationOpen = true
        var bans: AdminStoreHealth = .idle
        var bannedCount = 0
        // الأجهزة (`AdminDeviceReachStore`)
        var devices: AdminStoreHealth = .idle
        var devicesTotal = 0
        var devicesReach = 0
        var devicesFailed = 0

        /// في البطاقة شيء يراه هذا الدور
        var showsCard: Bool { seesSms || seesRegistration || seesDevices }
    }

    /// مخزن لم يُجلب هنا بعد وفي الذاكرة بياناته من صفحة أخرى: كلمة فوراً لا هيكل يومض قبل أول جلب
    static func seeded(_ health: AdminStoreHealth, hasData: Bool, now: Date = Date()) -> AdminStoreHealth {
        health == .idle && hasData ? .loaded(at: now) : health
    }

    // MARK: رأس بطاقة الحالة

    /// ما يحتاج المالك (Autoplan note 4): الرصيد منخفض أو عاجل · محاولات مريبة لم تُقرأ · التسجيل متوقف · تسجيلات أجهزة
    /// فاشلة. لا يُعدّ إلا ما وصلت بياناته (ولو قديمة)
    static func issueCount(_ f: Facts) -> Int {
        var n = 0
        if f.seesSms && f.sms.hasData && (f.smsLevel == .low || f.smsLevel == .urgent) { n += 1 }
        if f.seesSms && f.suspicious > 0 { n += 1 }
        if f.seesRegistration && f.settings.hasData && !f.registrationOpen { n += 1 }
        if f.seesDevices && f.devices.hasData && f.devicesFailed > 0 { n += 1 }
        return n
    }

    /// حال كلمة الرأس: مخازن الصفوف الظاهرة معاً (فشل بلا بيانات يغلب ← «تعذّر التحميل»)
    static func headHealth(_ f: Facts) -> AdminStoreHealth {
        var list: [AdminStoreHealth] = []
        if f.seesSms { list.append(f.sms) }
        if f.seesRegistration { list.append(f.settings) }
        if f.seesDevices { list.append(f.devices) }
        return AdminStoreHealth.combined(list)
    }

    /// «سليم ✓» أو «شيئان يحتاجانك»
    static func headWord(issues: Int) -> Word {
        guard issues > 0 else { return Word(text: L10n.t("سليم", "All good"), tone: .ok, icon: "checkmark") }
        let text: String
        switch issues {
        case 1:  text = L10n.t("شيء يحتاجك", "1 thing needs you")
        case 2:  text = L10n.t("شيئان يحتاجانك", "2 things need you")
        default: text = L10n.t("\(issues) أشياء تحتاجك", "\(issues) things need you")
        }
        return Word(text: text, tone: .warn, icon: "exclamationmark.circle.fill")
    }

    // MARK: الصفوف

    /// حبّة الرصيد: «جيد» · «منخفض» · «عاجل» (بلا قراءة: «لا قراءة»)
    static func smsWord(_ level: SmsLevel) -> Word {
        switch level {
        case .good:    return Word(text: L10n.t("جيد", "Good"), tone: .ok)
        case .low:     return Word(text: L10n.t("منخفض", "Low"), tone: .warn)
        case .urgent:  return Word(text: L10n.t("عاجل", "Urgent"), tone: .error)
        case .unknown: return Word(text: L10n.t("لا قراءة", "No reading"), tone: .off)
        }
    }

    /// «1,240 نقطة · تكفي نحو 18 يوماً» — «—» أثناء التحميل، و«تعذّر جلب الرصيد» حين فشل بلا بيانات
    static func smsLine(_ f: Facts) -> String {
        switch f.sms.look {
        case .skeleton: return AdminStoreHealthText.placeholder
        case .unknown:  return L10n.t("تعذّر جلب الرصيد", "Couldn't get the balance")
        case .hidden:   return ""
        case .word, .staleWord:
            guard let balance = f.balance else { return L10n.t("لا قراءة للرصيد بعد", "No balance reading yet") }
            let points = AdminNumberText.grouped(Int(balance.rounded(.down)))
            var line = L10n.t("\(points) نقطة", "\(points) points")
            if let days = f.daysLeft {
                line += L10n.t(" · تكفي نحو \(Self.days(days))", " · lasts about \(Self.days(days))")
            }
            return line
        }
    }

    /// «3 جديدة» — محاولات مريبة لم تُقرأ
    static func suspiciousWord(_ n: Int) -> Word {
        Word(text: L10n.t("\(AdminNumberText.grouped(n)) جديدة", "\(AdminNumberText.grouped(n)) new"), tone: .error)
    }

    /// «مسموح» / «متوقف»
    static func registrationWord(open: Bool) -> Word {
        open ? Word(text: L10n.t("مسموح", "Open"), tone: .ok)
             : Word(text: L10n.t("متوقف", "Stopped"), tone: .warn)
    }

    /// «12 رقماً ممنوعاً» — من مخزن المنع
    static func registrationLine(_ f: Facts) -> String {
        switch f.bans.look {
        case .skeleton: return AdminStoreHealthText.placeholder
        case .unknown:  return L10n.t("تعذّر جلب الأرقام الممنوعة", "Couldn't get the blocked numbers")
        case .hidden:   return ""
        case .word, .staleWord: return bannedLine(f.bannedCount)
        }
    }

    /// «لا أرقام ممنوعة» · «رقم واحد ممنوع» · «رقمان ممنوعان» · «3 أرقام ممنوعة» · «12 رقماً ممنوعاً» · «100 رقم ممنوع»
    static func bannedLine(_ n: Int) -> String {
        guard L10n.isArabic else {
            return n == 0 ? "No blocked numbers" : (n == 1 ? "1 blocked number" : "\(AdminNumberText.grouped(n)) blocked numbers")
        }
        switch n {
        case 0: return "لا أرقام ممنوعة"
        case 1: return "رقم واحد ممنوع"
        case 2: return "رقمان ممنوعان"
        default: return arabicCount(n, few: "أرقام ممنوعة", many: "رقماً ممنوعاً", single: "رقم ممنوع")
        }
    }

    /// اسم العدد في سطر رأس صفحة المنع (الرقم قبله منفصلاً): «أرقام ممنوعة» · «رقماً ممنوعاً» · «رقم ممنوع»
    static func bannedLabel(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "blocked number" : "blocked numbers" }
        switch n % 100 {
        case 3...10:  return "أرقام ممنوعة"
        case 11...99: return "رقماً ممنوعاً"
        default:      return n == 0 ? "أرقام ممنوعة" : "رقم ممنوع"
        }
    }

    /// حبّة الأجهزة: نسبة الوصول («93٪») — تحذير حين توجد تسجيلات فاشلة، و«لا أجهزة» بلا تسجيل
    static func devicesWord(_ f: Facts) -> Word {
        guard f.devicesTotal > 0 else { return Word(text: L10n.t("لا أجهزة", "No devices"), tone: .off) }
        let percent = Int((Double(f.devicesReach) / Double(f.devicesTotal) * 100).rounded(.down))
        return Word(text: L10n.t("\(percent)٪", "\(percent)%"), tone: f.devicesFailed > 0 ? .warn : .ok)
    }

    /// «تصل 412 جهازاً من 443 · 31 لا تصلها»
    static func devicesLine(_ f: Facts) -> String {
        switch f.devices.look {
        case .skeleton: return AdminStoreHealthText.placeholder
        case .unknown:  return L10n.t("تعذّر جلب الأجهزة", "Couldn't get the devices")
        case .hidden:   return ""
        case .word, .staleWord:
            guard f.devicesTotal > 0 else { return L10n.t("لا أجهزة مسجّلة بعد", "No registered devices yet") }
            let total = AdminNumberText.grouped(f.devicesTotal)
            var line: String
            if L10n.isArabic {
                switch f.devicesReach {
                case 0:  line = "لا تصل أي جهاز من \(total)"
                case 1:  line = "تصل جهازاً واحداً من \(total)"
                case 2:  line = "تصل جهازين من \(total)"
                default: line = "تصل \(arabicCount(f.devicesReach, few: "أجهزة", many: "جهازاً", single: "جهاز")) من \(total)"
                }
            } else {
                line = "Reaches \(AdminNumberText.grouped(f.devicesReach)) of \(total) devices"
            }
            if f.devicesFailed > 0 {
                let failed = AdminNumberText.grouped(f.devicesFailed)
                line += L10n.t(" · \(failed) لا تصلها", " · \(failed) don't")
            }
            return line
        }
    }

    // MARK: فريق الإدارة

    /// صفّ دور في بطاقة الفريق: «المالكان 2»، و«لا أحد بعد» باهتاً
    struct RoleRow: Hashable {
        let id: String
        let label: String
        let value: String
        let muted: Bool
    }

    /// «7 في الإدارة»
    static func teamHeadline(_ total: Int) -> String {
        L10n.t("\(AdminNumberText.grouped(total)) في الإدارة", "\(AdminNumberText.grouped(total)) on the admin team")
    }

    /// صفوف الأدوار بترتيبها، والأدوار بلا أحد صفّ واحد آخرها («المراقبون والمشرفون — لا أحد بعد»)
    static func teamRows(owners: Int, admins: Int, monitors: Int, supervisors: Int) -> [RoleRow] {
        struct Role { let id: String; let one: String; let two: String; let many: String; let count: Int }
        let roles = [
            Role(id: "owner", one: L10n.t("المالك", "Owner"), two: L10n.t("المالكان", "Owners"),
                 many: L10n.t("المُلّاك", "Owners"), count: owners),
            Role(id: "admin", one: L10n.t("المدير", "Admin"), two: L10n.t("المديران", "Admins"),
                 many: L10n.t("المديرون", "Admins"), count: admins),
            Role(id: "monitor", one: L10n.t("المراقب", "Monitor"), two: L10n.t("المراقبان", "Monitors"),
                 many: L10n.t("المراقبون", "Monitors"), count: monitors),
            Role(id: "supervisor", one: L10n.t("المشرف", "Supervisor"), two: L10n.t("المشرفان", "Supervisors"),
                 many: L10n.t("المشرفون", "Supervisors"), count: supervisors)
        ]
        var rows: [RoleRow] = []
        var empty: [Role] = []
        for role in roles {
            guard role.count > 0 else { empty.append(role); continue }
            let label = role.count == 1 ? role.one : (role.count == 2 ? role.two : role.many)
            rows.append(RoleRow(id: role.id, label: label, value: AdminNumberText.grouped(role.count), muted: false))
        }
        if !empty.isEmpty {
            let names = empty.map(\.many)
            let joined: String
            if L10n.isArabic {
                joined = names.joined(separator: " و")
            } else {
                joined = names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + names.last!.lowercased()
                                         : names[0]
            }
            rows.append(RoleRow(id: empty.map(\.id).joined(separator: "+"), label: joined,
                                value: L10n.t("لا أحد بعد", "No one yet"), muted: true))
        }
        return rows
    }

    // MARK: الاستخدام

    /// «96 نشطون»
    static func usageHeadline(active: Int) -> String {
        guard L10n.isArabic else { return "\(AdminNumberText.grouped(active)) active" }
        switch active {
        case 0:  return "لا أحد نشط"
        case 1:  return "نشط واحد"
        case 2:  return "نشطان"
        default: return "\(AdminNumberText.grouped(active)) نشطون"
        }
    }

    /// «من 171 حساباً» — كل حسابات الدخول المسمّاة (نشط + خامل + دخل بلا جهاز من «استخدام التطبيق»)، ومنها حسابات من خارج
    /// العائلة. ليست «في التطبيق» (170 في «الإحصاءات» و«اليوم» = أحياء العائلة المسجّلون، `setFamilyAccounts`)، فلا تُسمّى
    /// «لهم حساب» فيبدو الرقمان شيئاً واحداً بعددين (F1)
    static func usageBaseLine(accounts: Int) -> String {
        guard accounts > 0 else { return L10n.t("لا حسابات بعد", "No accounts yet") }
        guard L10n.isArabic else {
            return accounts == 1 ? "of 1 account" : "of \(AdminNumberText.grouped(accounts)) accounts"
        }
        switch accounts {
        case 1:  return "من حساب واحد"
        case 2:  return "من حسابين"
        default: return "من " + arabicCount(accounts, few: "حسابات", many: "حساباً", single: "حساب")
        }
    }

    // MARK: الأعداد

    /// «5 أيام» · «12 يوماً» · «يوم واحد» · «يومين» · «أقل من يوم»
    static func days(_ n: Int) -> String {
        guard L10n.isArabic else { return n == 1 ? "1 day" : "\(AdminNumberText.grouped(n)) days" }
        switch n {
        case ..<1: return "أقل من يوم"
        case 1:    return "يوم واحد"
        case 2:    return "يومين"
        default:   return arabicCount(n, few: "أيام", many: "يوماً", single: "يوم")
        }
    }

    /// العدد واسمه بقاعدة العربية (٣–١٠ جمع، ١١–٩٩ مفرد منصوب، والباقي مفرد) — الرقم بفاصل الآلاف
    static func arabicCount(_ n: Int, few: String, many: String, single: String) -> String {
        let number = AdminNumberText.grouped(n)
        switch n % 100 {
        case 3...10:  return "\(number) \(few)"
        case 11...99: return "\(number) \(many)"
        default:      return "\(number) \(single)"
        }
    }
}

#if !ADMIN_LOGIC_TEST

// MARK: - محوّلات حال المخزن (Autoplan note 2) — مخزنان بلا وحدة (T0) يقرؤهما القسم و«اليوم»

/// وقت آخر جلب ناجح لرصيد الرسائل في هذه الجلسة («آخر تحديث» حين يفشل التحديث التالي)
@MainActor
enum AdminTeamClock {
    static var smsLoadedAt: Date?
}

extension SmsBalanceStore {
    /// حال المخزن: التحديث فوق بيانات موجودة لا يرجع لهيكل؛ 42501 = مرفوض لدورك (بلا «أعد المحاولة»)
    var adminHealth: AdminStoreHealth {
        let stamp = AdminTeamClock.smsLoadedAt ?? status?.at
        let hasData = status != nil
        switch state {
        case .denied:          return .denied
        case .idle, .loading:  return hasData ? .loaded(at: stamp ?? Date()) : (state == .idle ? .idle : .loading)
        case .loaded:          return .loaded(at: stamp ?? Date())
        case .failed:          return .failed(lastGood: hasData ? (stamp ?? Date()) : nil)
        }
    }

    var adminLevel: AdminTeamLogic.SmsLevel {
        switch level {
        case .unknown: return .unknown
        case .good:    return .good
        case .low:     return .low
        case .urgent:  return .urgent
        }
    }
}

extension AdminDeviceReachStore {
    /// حال المخزن: إعادة المحاولة بلا بيانات = هيكل؛ الفشل فوق بيانات = الكلمة + «آخر تحديث»
    var adminHealth: AdminStoreHealth {
        guard rows != nil else {
            if isLoading { return .loading }
            return failed ? .failed(lastGood: nil) : .idle
        }
        return failed ? .failed(lastGood: loadedAt) : .loaded(at: loadedAt ?? Date())
    }
}

extension AdminTeamLogic.Tone {
    var pill: AdminPillTone {
        switch self {
        case .ok:    return .ok
        case .off:   return .off
        case .warn:  return .warn
        case .error: return .error
        }
    }
}

// MARK: - الصفحة

/// «الفريق والصلاحيات» (ترتيب المالك ٢٠٢٦-١١-٢٨): «الفريق» (فريق الإدارة) ← «الأعضاء» (صلاحيات الأعضاء حسب الفئة ·
/// التسجيل والمنع). رسائل رمز الدخول والأجهزة انتقلت إلى «التطبيق والنظام ← النظام»، و«الاستخدام» إلى «الإحصاءات ← في
/// التطبيق» — بنفس خاناتها في جدول الأدوار
struct AdminTeamAreaView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @ObservedObject private var config = AppConfigValues.shared

    private var seesTeam: Bool { authVM.adminSees(.teamMembers) }
    private var seesRegistration: Bool { authVM.adminSees(.teamRegistration) }

    var body: some View {
        let tiles = AdminGroupTilesLogic.teamTiles(seesTeam: seesTeam, isOwner: authVM.isOwner,
                                                   seesRegistration: seesRegistration)
        AdminHubPage {
            AdminBandHeader(title: AdminArea.team.title, subtitle: AdminArea.team.subtitle,
                            badge: authVM.adminCanEdit(.team) ? nil : AdminPageHeader.readOnlyText,
                            isAreaRoot: true)
        } content: {
            if tiles.isEmpty {
                // الجدول أخفى كل ما في القسم عن هذا الدور — حالة فارغة لا صفحة بيضاء
                AnyView(AdminPageStateCard(.empty(L10n.t("لا شيء هنا لدورك", "Nothing here for your role"),
                                                  message: L10n.t("صلاحياتك في «صلاحياتي» على «اليوم»",
                                                                  "Your permissions are under “My scope” on Today"))))
            } else {
                // كل مجموعة مربّع (طلب المالك ٢٠٢٦-١١-٢٨ «المجموعات بشكل مربعات»)
                AnyView(AdminGroupTilesSection(items: tiles.map(item)))
            }
        }
        // ما يُدفع من المربّعات يرجع باسم القسم
        .environment(\.adminPageTitle, AdminArea.team.title)
        .refreshable { await load(force: true) }
        .task { await load(force: false) }
        .debugStackProbe("AdminTeamAreaView", limitKB: DebugStackLimit.page)
    }

    /// الأعضاء (عدد الفريق) — هنا فقط إن لم يصلوا بعد (لا جلب ثقيل لكل الشجرة مع كل ظهور)، والتسجيل والمنع لسطر مربّعه
    private func load(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            if seesTeam, force || memberVM.allMembers.isEmpty {
                group.addTask { @MainActor in await memberVM.fetchAllMembers(force: force) }
            }
            if seesRegistration {
                group.addTask { @MainActor in await appSettingsVM.fetchSettings() }
                group.addTask { @MainActor in await authVM.fetchBannedPhones() }
            }
            if authVM.isOwner { group.addTask { @MainActor in await AppConfigValues.shared.refresh(force: force) } }
        }
    }

    private func item(_ tile: AdminTeamTile) -> AdminGroupTileItem {
        var number: String?
        var status: String?
        var tone = AdminGroupStatusTone.plain
        let fill: Color
        let ink: Color
        let page: () -> AnyView
        switch tile {
        case .team:
            fill = DS.Color.navyFill
            ink = DS.Color.primary
            if !memberVM.allMembers.isEmpty {
                let staff = memberVM.allMembers.filter {
                    $0.isDeceased != true && [.owner, .admin, .monitor, .supervisor].contains($0.role)
                }
                number = AdminNumberText.grouped(staff.count)
            } else if memberVM.membersLoadFailed {
                number = AdminStoreHealthText.placeholder
            }
            status = L10n.t("الأدوار وصلاحياتها", "Roles and their permissions")
            page = { AnyView(AdminModeratorsView()) }
        case .memberAccess:
            fill = DS.Color.palmFill
            ink = DS.Color.palm
            let matrix = MemberAccessStore.shared.matrix
            let custom = MemberCategory.allCases.filter { MemberAccess.isCustom(category: $0, matrix: matrix) }.count
            number = AdminNumberText.grouped(MemberCategory.allCases.count)
            status = custom > 0 ? L10n.t("\(custom) مخصّص", "\(custom) custom") : L10n.t("حسب الفئة", "By category")
            tone = custom > 0 ? .warn : .plain
            page = { AnyView(AdminTeamGroupPage(tile: .memberAccess)) }
        case .registration:
            fill = DS.Color.slateFill
            ink = DS.Color.slate
            if appSettingsVM.settings.updatedAt != nil {
                let word = AdminTeamLogic.registrationWord(open: appSettingsVM.settings.allowNewRegistrations)
                let banned = authVM.bannedPhones.count
                // قصير ليبقى سطراً واحداً: «مسموح» أو «مسموح · 3 ممنوع» (التفصيل في صفحتها)
                status = banned == 0 ? word.text
                    : word.text + " · " + L10n.t("\(AdminNumberText.grouped(banned)) ممنوع",
                                                 "\(AdminNumberText.grouped(banned)) blocked")
                tone = word.tone == .ok ? .plain : .warn
            }
            page = { AnyView(AdminRegistrationBansView()) }
        }
        return AdminGroupTileItem(id: "team." + tile.rawValue, title: tile.title, icon: tile.icon, fill: fill, ink: ink,
                                  number: number, status: status, tone: tone, backTitle: AdminArea.team.title,
                                  area: .team, page: page)
    }
}

/// صفحة مجموعة من «الفريق والصلاحيات» — «صلاحيات الأعضاء حسب الفئة» (المالك وحده — `MemberAccessAdminPage.swift`)
struct AdminTeamGroupPage: View {
    let tile: AdminTeamTile

    var body: some View {
        AdminGroupPage(title: tile.title, subtitle: L10n.t("ما تراه كل فئة من الأعضاء", "What each member category sees")) {
            AnyView(MemberAccessCategoriesCard())
        }
        .debugStackProbe("AdminTeamGroupPage", limitKB: DebugStackLimit.page)
    }
}

// MARK: - بطاقة الحال لبيوت الدخول (مشتركة: «الفريق والصلاحيات» و«التطبيق والنظام»)

/// بطاقة حال بيوت «الدخول»: صفّ لكل بيت بكلمة حاله من مخزنه (رسائل رمز الدخول · محاولات مريبة · التسجيل والمنع · الأجهزة
/// والإشعارات). كانت كلها في «الفريق والأمان»؛ منذ ٢٠٢٦-١١-٢٨ التسجيل في «الفريق والصلاحيات» والباقي في «التطبيق والنظام ←
/// النظام». كل صفّ بخانته في جدول الأدوار كما كان (`team.sms`/`team.registration`/`team.devices` — للمالك)، وتجلب البطاقة
/// مخازنها هي — كل مخزن وحده (فشل واحد لا يوقف الباقي)
struct AdminAccessStatusSection: View {
    enum Row: Hashable { case sms, registration, devices }

    let rows: Set<Row>
    let title: String
    /// يزيد مع سحب الصفحة للتحديث — البطاقة تعيد جلب مخازنها بالقوة
    var refreshToken: Int = 0

    static var registrationTitle: String { L10n.t("التسجيل", "Sign-up") }
    static var systemTitle: String { L10n.t("الدخول والإشعارات", "Sign-in and notifications") }

    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var sms = SmsBalanceStore.shared
    @ObservedObject private var devices = AdminDeviceReachStore.shared
    /// إعدادات التسجيل (`fetchSettings` لا يُبلغ الفشل — وصلت = `updatedAt`)
    @State private var settingsHealth: AdminStoreHealth = .idle
    /// الأرقام الممنوعة (`fetchBannedPhones` لا يُبلغ الفشل — انتهى بلا اتصال = فشل، كصفحة المنع)
    @State private var bansHealth: AdminStoreHealth = .idle

    private var seesSms: Bool { rows.contains(.sms) && authVM.adminSees(.teamSms) }
    private var seesRegistration: Bool { rows.contains(.registration) && authVM.adminSees(.teamRegistration) }
    private var seesDevices: Bool { rows.contains(.devices) && authVM.adminSees(.teamDevices) }

    var body: some View {
        let facts = self.facts
        if facts.showsCard {
            AdminTeamStatusCard(title: title, facts: facts, retry: retryFailed)
                .task { await reload(force: false) }
                .onChange(of: refreshToken) { _ in Task { await reload(force: true) } }
        }
    }

    private var facts: AdminTeamLogic.Facts {
        let reach = devices.stats
        return AdminTeamLogic.Facts(
            seesSms: seesSms, seesRegistration: seesRegistration, seesDevices: seesDevices,
            sms: sms.adminHealth, smsLevel: sms.adminLevel, balance: sms.status?.balance,
            daysLeft: sms.overview?.daysLeft,
            suspicious: notificationVM.notifications.filter { !$0.read && $0.kind == AdminNotices.smsSuspicious }.count,
            settings: AdminTeamLogic.seeded(settingsHealth, hasData: appSettingsVM.settings.updatedAt != nil),
            registrationOpen: appSettingsVM.settings.allowNewRegistrations,
            bans: AdminTeamLogic.seeded(bansHealth, hasData: !authVM.bannedPhones.isEmpty), bannedCount: authVM.bannedPhones.count,
            devices: devices.adminHealth, devicesTotal: reach?.total ?? 0, devicesReach: reach?.reach ?? 0,
            devicesFailed: reach?.invalid ?? 0)
    }

    private func reload(force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            if seesSms { group.addTask { @MainActor in await loadSms(force: force) } }
            if seesDevices { group.addTask { @MainActor in await devices.refresh(force: force) } }
            if seesRegistration {
                group.addTask { @MainActor in await loadSettings() }
                group.addTask { @MainActor in await loadBans() }
            }
        }
    }

    /// «تعذّر التحميل ↻» في رأس البطاقة: يعيد جلب ما فشل وحده
    private func retryFailed() {
        Task {
            await withTaskGroup(of: Void.self) { group in
                if seesSms, sms.adminHealth.canRetry { group.addTask { @MainActor in await loadSms(force: true) } }
                if seesDevices, devices.adminHealth.canRetry {
                    group.addTask { @MainActor in await devices.refresh(force: true) }
                }
                if seesRegistration, settingsHealth.canRetry { group.addTask { @MainActor in await loadSettings() } }
                if seesRegistration, bansHealth.canRetry { group.addTask { @MainActor in await loadBans() } }
            }
        }
    }

    private func loadSms(force: Bool) async {
        await sms.refresh(force: force)
        if sms.state == .loaded, force || AdminTeamClock.smsLoadedAt == nil { AdminTeamClock.smsLoadedAt = Date() }
    }

    private func loadSettings() async {
        settingsHealth = AdminTeamLogic.seeded(settingsHealth, hasData: appSettingsVM.settings.updatedAt != nil).beginning()
        await appSettingsVM.fetchSettings()
        settingsHealth = settingsHealth.ending(success: appSettingsVM.settings.updatedAt != nil)
    }

    private func loadBans() async {
        bansHealth = AdminTeamLogic.seeded(bansHealth, hasData: !authVM.bannedPhones.isEmpty).beginning()
        await authVM.fetchBannedPhones()
        bansHealth = bansHealth.ending(success: NetworkMonitor.shared.isConnected)
    }
}

// MARK: - «الاستخدام» في «الإحصاءات ← في التطبيق» (انتقل من «الفريق والأمان» ٢٠٢٦-١١-٢٨)

/// بطاقة «الاستخدام» بجلبها (`AppUsageStats`) — تظهر لمن خانته `team.usage` (المالك والمدير) كما كانت
struct AdminUsageSection: View {
    @State private var usage: AppUsageStats? = AppUsageStats.cached
    @State private var usageHealth: AdminStoreHealth = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("الاستخدام", "Usage"),
                              trailing: L10n.t("نشط = دخل خلال 3 أسابيع", "Active = signed in within 3 weeks"))
            AdminTeamUsageCard(usage: usage, health: usageHealth, retry: { Task { await loadUsage() } })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await loadUsage() }
    }

    /// `AppUsageStats.fetch` يرجع آخر قيمة عند الفشل — nil = لا شيء أبداً
    private func loadUsage() async {
        usageHealth = usageHealth.beginning()
        #if DEBUG
        if DebugAdminProbe.shouldFail(.usage, hasLoaded: usage != nil) {   // `-tmpFailStores usage`
            usageHealth = usageHealth.ending(success: false)
            return
        }
        #endif
        if let fetched = await AppUsageStats.fetch() {
            usage = fetched
            usageHealth = usageHealth.ending(success: true)
        } else {
            usageHealth = usageHealth.ending(success: false)
        }
    }
}

// MARK: - بطاقة الحالة «الدخول والأمان»

/// رأسها حبّة كلمة بحال مخازنها، وتحتها صفّ لكل بيت — الصفّ كله لمسة واحدة تفتح بيته (الحبّة جزء منه — spec A.7)
struct AdminTeamStatusCard: View {
    var title: String = L10n.t("الدخول والأمان", "Sign-in and security")
    let facts: AdminTeamLogic.Facts
    /// حبّة الرأس «تعذّر التحميل ↻» تعيد جلب ما فشل
    let retry: () -> Void

    var body: some View {
        let head = AdminTeamLogic.headWord(issues: AdminTeamLogic.issueCount(facts))
        AdminSectionCard(title: title, spacing: 0,
                         status: AdminStatePill(health: AdminTeamLogic.headHealth(facts), title: head.text,
                                                tone: head.tone.pill, icon: head.icon, retry: retry)) {
            AdminRowsCardBody {
                if facts.seesSms {
                    row(icon: "ellipsis.message.fill", tint: DS.Hub.securityFill,
                        title: L10n.t("رسائل رمز الدخول", "Sign-in code messages"),
                        line: AdminTeamLogic.smsLine(facts),
                        word: AdminTeamLogic.smsWord(facts.smsLevel), health: facts.sms) { AnyView(AdminSmsView()) }
                    if facts.suspicious > 0 {
                        row(icon: "exclamationmark.triangle.fill", tint: DS.Hub.securityFill,
                            title: L10n.t("محاولات دخول مريبة", "Suspicious sign-in attempts"),
                            line: L10n.t("5 طلبات للرمز أو أكثر خلال ساعة", "5 or more code requests within an hour"),
                            word: AdminTeamLogic.suspiciousWord(facts.suspicious), health: nil) {
                            AnyView(SmsAttemptsListPage())
                        }
                    }
                }
                if facts.seesRegistration {
                    row(icon: "person.badge.plus", tint: DS.Color.navyFill,
                        title: L10n.t("التسجيل والمنع", "Sign-up and blocking"),
                        line: AdminTeamLogic.registrationLine(facts),
                        word: AdminTeamLogic.registrationWord(open: facts.registrationOpen), health: facts.settings) {
                        AnyView(AdminRegistrationBansView())
                    }
                }
                if facts.seesDevices {
                    row(icon: "iphone", tint: DS.Color.sea,
                        title: L10n.t("الأجهزة والإشعارات", "Devices and notifications"),
                        line: AdminTeamLogic.devicesLine(facts),
                        word: AdminTeamLogic.devicesWord(facts), health: facts.devices) { AnyView(AdminPushHealthView()) }
                }
            }
        }
    }

    /// صفّ: مربّع الأيقونة + الاسم وسطر رقمه + حبّة الحال + سهم — يفتح بيته (خلف `AdminLazyPage` عبر `AdminTapWrap`)
    private func row(icon: String, tint: Color, title: String, line: String, word: AdminTeamLogic.Word,
                     health: AdminStoreHealth?, page: @escaping () -> AnyView) -> some View {
        let pill = health.map { AdminStatePill(health: $0, title: word.text, tone: word.tone.pill, icon: word.icon) }
            ?? AdminStatePill(title: word.text, tone: word.tone.pill, icon: word.icon)
        return AdminTapWrap(tap: .page(page), feel: .row, label: AnyView(
            AdminListRow(icon: icon, tint: tint, title: title, subtitle: line) { pill.fixedSize() }
        ))
    }
}

// MARK: - بطاقة «فريق الإدارة»

/// «7 في الإدارة» ثم عدد كل دور — البطاقة كلها باب واحد إلى صفحة الفريق (بيت الإضافة وتغيير الدور والإزالة)
struct AdminTeamMembersCard: View {
    /// المالك يعدّل (`canManageRoles` × «يعدّل» في الجدول) — يغيّر سطر الوصف فقط؛ الأوامر في صفحة الفريق
    let canEdit: Bool
    @EnvironmentObject var memberVM: MemberViewModel

    var body: some View {
        if memberVM.allMembers.isEmpty {
            if memberVM.membersLoadFailed {
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل فريق الإدارة", "Couldn't load the admin team"),
                                          message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                          retry: { Task { await memberVM.fetchAllMembers(force: true) } }))
            } else {
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل فريق الإدارة", "Loading the admin team"), rows: 3))
            }
        } else {
            card
        }
    }

    private var card: some View {
        let staff = memberVM.allMembers.filter { $0.isDeceased != true }
        func n(_ role: FamilyMember.UserRole) -> Int { staff.filter { $0.role == role }.count }
        let counts = (owner: n(.owner), admin: n(.admin), monitor: n(.monitor), supervisor: n(.supervisor))
        let total = counts.owner + counts.admin + counts.monitor + counts.supervisor
        let rows = AdminTeamLogic.teamRows(owners: counts.owner, admins: counts.admin,
                                           monitors: counts.monitor, supervisors: counts.supervisor)
        let shape = RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
        return AdminTapWrap(tap: .page { AnyView(AdminModeratorsView()) }, feel: .row, label: AnyView(
            AdminRowsCardBody(dividerInset: 0) {
                HStack(spacing: DS.Spacing.md) {
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(verbatim: AdminTeamLogic.teamHeadline(total))
                            .dsFont(.body)
                            .monospacedDigit()
                            .foregroundColor(DS.Color.textPrimary)
                        Text(canEdit ? L10n.t("الإضافة وتغيير الدور وصلاحيات الأدوار في الداخل",
                                              "Adding, changing roles and role permissions are inside")
                                     : L10n.t("الأعضاء حسب الدور، وصلاحيات الأدوار", "Members by role, and role permissions"))
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DS.Spacing.xs)
                    DSChevron()
                }
                .padding(.vertical, DS.Spacing.xsm)
                .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
                ForEach(rows, id: \.id) { row in
                    HStack(spacing: DS.Spacing.md) {
                        Text(verbatim: row.label)
                            .dsFont(.body)
                            .foregroundColor(row.muted ? DS.Color.textTertiary : DS.Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: DS.Spacing.xs)
                        if row.muted {
                            Text(verbatim: row.value)
                                .dsFont(.subtitle)
                                .foregroundColor(DS.Color.textTertiary)
                        } else {
                            AdminRowValue(text: row.value)
                        }
                    }
                    .frame(minHeight: DS.Hub.rowMinHeight)
                }
            }
            .padding(DS.Hub.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(L10n.t("يفتح فريق الإدارة", "Opens the admin team"))
        ))
        .clipShape(shape)
        .adminCard(padding: 0)
    }
}

// MARK: - بطاقة «الاستخدام»

/// «96 نشطون» · «من 171 حساباً» (كل الحسابات — لا «لهم حساب»، F1) + شريط ٣ أجزاء بصفوف ألوانه (بدل المفتاح) + «تفاصيل الاستخدام ‹»
struct AdminTeamUsageCard: View {
    let usage: AppUsageStats?
    let health: AdminStoreHealth
    let retry: () -> Void

    private struct Part: Identifiable {
        let id: String
        let label: String
        let value: Int
        let tint: Color
    }

    var body: some View {
        if let usage {
            card(usage)
        } else if case .failed = health {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل أرقام الاستخدام", "Couldn't load usage numbers"),
                                      message: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                                      retry: retry))
        } else {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل أرقام الاستخدام", "Loading usage numbers"), rows: 3))
        }
    }

    private func card(_ u: AppUsageStats) -> some View {
        let parts = [
            Part(id: "active", label: L10n.t("نشط", "Active"), value: u.active, tint: DS.Color.primaryFill),
            Part(id: "idle", label: L10n.t("خامل", "Idle"), value: u.idle, tint: DS.Color.textTertiary),
            Part(id: "noDevice", label: L10n.t("دخل بلا جهاز", "Signed in, no device"), value: u.loginNoDevice,
                 tint: DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
        ]
        let accounts = u.active + u.idle + u.loginNoDevice
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: AdminTeamLogic.usageHeadline(active: u.active))
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                Text(verbatim: AdminTeamLogic.usageBaseLine(accounts: accounts))
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
            }
            .accessibilityElement(children: .combine)
            DSMeterBar(parts: DSGaugePart.counts(parts.map { ($0.id, $0.value, $0.tint) }), track: DS.Chart.inkTrack)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xs)
            AdminRowsCardBody(dividerInset: 0) {
                ForEach(parts) { part in
                    HStack(spacing: DS.Spacing.sm) {
                        RoundedRectangle(cornerRadius: DS.Spacing.xxs, style: .continuous)
                            .fill(part.tint)
                            .frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
                            .accessibilityHidden(true)
                        Text(part.label)
                            .dsFont(.body)
                            .foregroundColor(DS.Color.textPrimary)
                        Spacer(minLength: DS.Spacing.xs)
                        AdminRowValue(text: AdminNumberText.grouped(part.value))
                    }
                    .frame(minHeight: DS.Hub.rowMinHeight)
                    .accessibilityElement(children: .combine)
                }
                AdminTapWrap(tap: .page { AnyView(AdminActiveMembersView()) }, feel: .row, label: AnyView(
                    HStack(spacing: DS.Spacing.sm) {
                        Text(L10n.t("تفاصيل الاستخدام", "Usage details"))
                            .dsFont(.body)
                            .foregroundColor(DS.Color.primary)
                        Spacer(minLength: DS.Spacing.xs)
                        DSChevron()
                    }
                    .frame(minHeight: DS.Hub.rowMinHeight)
                    .contentShape(Rectangle())
                ))
            }
            if case .failed(let since?) = health {
                AdminStaleStamp(since: since)
                    .padding(.top, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }
}

#endif
