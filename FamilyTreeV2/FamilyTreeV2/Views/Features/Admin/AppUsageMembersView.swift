import SwiftUI
import Supabase

// MARK: - استخدام التطبيق — من هم أعضاء كل فئة ولماذا (طلب المالك)
//
// تُفتح من بطاقة «استخدام التطبيق» في لوحة الإدارة ومن «إعدادات التطبيق».
// العضو الفعّال = رقم + جهاز دخل التطبيق (تعريف المالك).

enum AppUsageCategory: String, CaseIterable, Identifiable {
    case active
    case idle
    case loginNoDevice = "login_no_device"
    case neverLogged = "never_logged"
    case noPhone = "no_phone"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:        return L10n.t("فعّال", "Active")
        case .idle:          return L10n.t("خامل", "Idle")
        case .loginNoDevice: return L10n.t("بلا جهاز مسجّل", "No registered device")
        case .neverLogged:   return L10n.t("ما دخل أبداً", "Never signed in")
        case .noPhone:       return L10n.t("بلا رقم", "No phone")
        }
    }

    var icon: String {
        switch self {
        case .active:        return "checkmark.seal.fill"
        case .idle:          return "moon.zzz.fill"
        case .loginNoDevice: return "iphone.slash"
        case .neverLogged:   return "phone.fill.arrow.up.right"
        case .noPhone:       return "phone.down.fill"
        }
    }

    var color: Color {
        switch self {
        case .active:        return DS.Color.success
        case .idle:          return DS.Color.warning
        case .loginNoDevice: return DS.Color.info
        case .neverLogged:   return DS.Color.textSecondary
        case .noPhone:       return DS.Color.textTertiary
        }
    }

    /// لماذا هم في هذه الفئة — يظهر أعلى القائمة
    var explanation: String {
        switch self {
        case .active:
            return L10n.t("لهم رقم وجهاز، ودخلوا التطبيق خلال آخر ٢١ يوماً. تصلهم الإشعارات.",
                          "Have a phone and a device, and opened the app in the last 21 days. They receive notifications.")
        case .idle:
            return L10n.t("لهم رقم وجهاز مسجّل، لكن ما دخلوا التطبيق من أكثر من ٢١ يوماً. تصلهم الإشعارات.",
                          "Have a phone and a registered device, but haven't opened the app in over 21 days. They still receive notifications.")
        case .loginNoDevice:
            return L10n.t("دخلوا التطبيق سابقاً وما بقى لهم جهاز مسجّل. الجهاز يُحذف تلقائياً إذا حذف العضو التطبيق من جواله (ترفض Apple الإشعار فيُمسح الجهاز)، أو إذا سجّل خروج، أو أزالته الإدارة. لا تصلهم الإشعارات.",
                          "Signed in before but no longer have a registered device. A device is removed automatically when the app is deleted from the phone (Apple rejects the notification), on sign-out, or when an admin removes it. They get no notifications.")
        case .neverLogged:
            return L10n.t("رقمهم موجود في الشجرة لكنهم ما سجّلوا دخول ولا مرة. ادعُهم للتطبيق.",
                          "Their number is in the tree but they've never signed in. Invite them to the app.")
        case .noPhone:
            return L10n.t("أسماء في الشجرة بلا رقم جوال — لا يقدرون يدخلون التطبيق حتى يُضاف رقمهم.",
                          "Names in the tree with no phone number — they can't sign in until a number is added.")
        }
    }
}

/// صف عضو من نتيجة app_usage_members
struct AppUsageMember: Decodable, Identifiable {
    let memberId: UUID
    let fullName: String?
    let phone: String?
    let lastSeen: Date?
    let accountCreated: Date?
    let hasLogin: Bool

    var id: UUID { memberId }

    enum CodingKeys: String, CodingKey {
        case memberId = "member_id"
        case fullName = "full_name"
        case phone
        case lastSeen = "last_seen"
        case accountCreated = "account_created"
        case hasLogin = "has_login"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        memberId = try c.decode(UUID.self, forKey: .memberId)
        fullName = try c.decodeIfPresent(String.self, forKey: .fullName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        hasLogin = try c.decodeIfPresent(Bool.self, forKey: .hasLogin) ?? false
        lastSeen = Self.parse(try c.decodeIfPresent(String.self, forKey: .lastSeen))
        accountCreated = Self.parse(try c.decodeIfPresent(String.self, forKey: .accountCreated))
    }

    private static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: raw) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: raw)
    }
}

/// أعضاء فئة من «استخدام التطبيق» — بشكل «اليوم» (طلب المالك ٢٠٢٦-١٠-٢٠، `AdminPageKit`):
/// رأس كحلي بأرقام حيّة ← «لماذا هم هنا؟» تصعد فوقه ← «الأعضاء» صفوفاً في بطاقة بيضاء
/// مع اتصال/واتساب سريع لمن له رقم. التحميل والسحب للتحديث كما كانا.
struct AppUsageMembersView: View {
    let category: AppUsageCategory
    @Environment(\.openURL) private var openURL

    @State private var members: [AppUsageMember] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        AdminPage(header: header, lead: AnyView(explanationSection), content: AnyView(listContent))
            .refreshable { await load() }
            .task { await load() }
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading {
            AdminPageStateCard(.loading(L10n.t("جارٍ تحميل القائمة…", "Loading the list…")))
        } else if loadFailed {
            AdminPageStateCard(.error(L10n.t("تعذّر تحميل القائمة. اسحب للتحديث.",
                                             "Couldn't load the list. Pull to refresh."),
                                      retry: {
                                          Task {
                                              isLoading = true
                                              await load()
                                          }
                                      }))
        } else if members.isEmpty {
            AdminPageStateCard(.empty(L10n.t("لا يوجد أحد في هذه الفئة.", "Nobody in this category.")))
        } else {
            membersSection
        }
    }

    // MARK: - بطاقة الرأس

    private var withPhoneCount: Int {
        members.filter { !($0.phone ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// نسبة الفئة من كل الأحياء — من آخر أرقام «استخدام التطبيق» المحفوظة (بلا طلب جديد)
    private var shareText: String {
        guard let u = AppUsageStats.cached else { return "—" }
        let total = AppUsageCategory.allCases.reduce(0) { $0 + u.value(for: $1) }
        guard total > 0 else { return "—" }
        let pct = Int((Double(u.value(for: category)) / Double(total) * 100).rounded())
        return L10n.t("\(pct)٪", "\(pct)%")
    }

    /// الأرقام بعد تحميل ناجح فقط — «—» أثناء التحميل أو بعد فشله (لا أصفار مضلِّلة)
    private var countsReady: Bool { !isLoading && !loadFailed }

    /// الرأس الكحلي: اسم الفئة ورمزها + الأرقام السريعة
    private var header: AdminPageHeader {
        AdminPageHeader(
            title: category.title,
            subtitle: L10n.t("فئة من «استخدام التطبيق» — الأحياء فقط",
                             "An “App usage” group — living members only"),
            glyph: category.icon,
            kpis: [
                AdminPageKPI(countsReady ? "\(members.count)" : "—", L10n.t("عضو", "Members"), icon: "person.2"),
                AdminPageKPI(countsReady ? "\(withPhoneCount)" : "—", L10n.t("لهم رقم", "With phone"), icon: "phone",
                             tint: DS.Hub.kpiMine),
                AdminPageKPI(shareText, L10n.t("من الأحياء", "Of living"), icon: "chart.pie", tint: DS.Hub.kpiLate)
            ])
    }

    // MARK: - لماذا هم هنا؟

    private var explanationSection: some View {
        AdminSectionCard(title: L10n.t("لماذا هم هنا؟", "Why are they here?")) {
            HStack(alignment: .top, spacing: DS.Spacing.md) {
                AdminIconSquare(symbol: category.icon, tint: category.color)
                Text(category.explanation)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - الأعضاء

    private var membersSection: some View {
        AdminSectionCard(title: L10n.t("الأعضاء", "Members"), tag: "\(members.count)", spacing: 0) {
            LazyVStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { AdminRowDivider() }
                    memberRow(member)
                }
            }
        }
    }

    private func memberRow(_ member: AppUsageMember) -> some View {
        let name = member.fullName ?? "—"
        return HStack(spacing: DS.Spacing.sm) {
            // الحرف الأول بلون الفئة (القائمة من السيرفر بلا صور) — صورة العضو الموحّدة
            DSMemberAvatar(name: name, avatarUrl: nil, size: DS.Icon.rowLarge, roleColor: category.color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(lastSeenText(member))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // دعوة سريعة للرجوع للتطبيق — اتصال أو واتساب
            if let phone = member.phone, !phone.isEmpty {
                contactButton(icon: "phone.fill", color: DS.Color.seaFill,
                              label: L10n.t("اتصال بـ \(name)", "Call \(name)")) {
                    let digits = phone.filter { $0.isNumber || $0 == "+" }
                    if let url = URL(string: "tel:\(digits)") { openURL(url) }
                }
                // أخضر من ألوان التطبيق (مثل «الرسائل») — أخضر واتساب الثابت باهت بالوضع الفاتح
                contactButton(icon: "message.fill", color: DS.Color.secondary,
                              label: L10n.t("واتساب \(name)", "WhatsApp \(name)")) {
                    let digits = phone.filter { $0.isNumber }
                    if let url = URL(string: "https://wa.me/\(digits)") { openURL(url) }
                }
            }
        }
        .padding(.vertical, DS.Spacing.sm)
        .frame(minHeight: DSBox.fieldMinHeight)
    }

    /// زرّ تواصل: قرص الحالة المجسّم بلون المعنى (اتصال/واتساب) داخل مساحة ضغط ٤٤
    private func contactButton(icon: String, color: Color, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSStateIcon(icon, tint: color, size: DS.Icon.rowCompact, mapsChrome: false)
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.vertical, -(DS.Icon.tapTarget - DS.Icon.rowCompact) / 2)
        .accessibilityLabel(label)
    }

    private func lastSeenText(_ member: AppUsageMember) -> String {
        if let seen = member.lastSeen {
            return L10n.t("آخر دخول: ", "Last seen: ") + Self.monthNameDate(seen)
        }
        if category == .noPhone {
            return L10n.t("بلا رقم جوال", "No phone number")
        }
        return L10n.t("ما دخل التطبيق أبداً", "Never opened the app")
    }

    /// التاريخ بالشهر نصاً: «٨ يونيو ٢٠٢٦» (طلب المالك)
    static func monthNameDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    private func load() async {
        do {
            let rows: [AppUsageMember] = try await SupabaseConfig.client
                .rpc("app_usage_members", params: ["p_category": category.rawValue])
                .execute()
                .value
            members = rows
            loadFailed = false
        } catch {
            loadFailed = true
            Log.fetchError("تعذر جلب أعضاء فئة الاستخدام", error)
        }
        isLoading = false
    }
}

// MARK: - بطاقة «استخدام التطبيق»

/// «استخدام التطبيق»: فعّال · بلا جهاز · ما دخل · دون رقم — كل فئة تفتح قائمتها (صفحة «الحسابات والاستخدام»؛
/// بطاقة قسم «العائلة» في `AdminAreaPages` نسختها القديمة — تُستبدل بهذه عند دمج الفرعين)
struct AdminUsageCard: View {
    let usage: AppUsageStats

    var body: some View {
        let u = usage
        let rows: [(AppUsageCategory, String, Int, Color)] = [
            (.active, L10n.t("فعّال (رقم وجهاز)", "Active (phone + device)"), u.active + u.idle, DS.Color.success),
            (.loginNoDevice, L10n.t("دخل بلا جهاز", "Signed in, no device"), u.loginNoDevice, DS.Color.info),
            (.neverLogged, L10n.t("ما دخل أبداً", "Never signed in"), u.neverLogged, DS.Color.warning),
            (.noPhone, L10n.t("دون رقم", "No phone"), u.noPhone, DS.Color.textTertiary)
        ]
        let total = rows.reduce(0) { $0 + $1.2 }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            AdminCardHeader(title: L10n.t("استخدام التطبيق", "App usage"))
            DSDistributionBar(segments: rows.map { .init(id: $0.0.rawValue, value: $0.2, tint: $0.3) },
                              height: DS.Spacing.md)
            Text(L10n.t("من \(total) حيّاً", "of \(total) living"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { AdminRowDivider() }
                    AdminTapWrap(tap: .page { AnyView(AppUsageMembersView(category: row.0)) }, feel: .plain,
                                 label: AnyView(usageRow(title: row.1, value: row.2, tint: row.3)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard()
    }

    private func usageRow(title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Circle().fill(tint).frame(width: DS.Icon.legendDot, height: DS.Icon.legendDot)
            Text(title)
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textPrimary)
            Spacer(minLength: DS.Spacing.sm)
            Text("\(value)")
                .dsFont(.chip)
                .monospacedDigit()
                .foregroundColor(tint.dsReadableGlyph)
            DSChevron()
        }
        .frame(minHeight: DS.Icon.tapTarget)
        .contentShape(Rectangle())
    }
}
