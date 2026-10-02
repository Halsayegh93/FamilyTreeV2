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

/// أعضاء فئة من «استخدام التطبيق» — بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧):
/// بطاقة رأس بأرقام حيّة ← «لماذا هم هنا؟» ← «الأعضاء» صفوفاً `.dsRowBox()`
/// مع اتصال/واتساب سريع لمن له رقم. التحميل والسحب للتحديث كما كانا.
struct AppUsageMembersView: View {
    let category: AppUsageCategory
    @Environment(\.openURL) private var openURL

    @State private var members: [AppUsageMember] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    /// لون مجال «الشجرة والأعضاء» (الرأس والأقسام) — ولون الفئة للأيقونات
    private let tint = DS.Color.composerProject

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    hero
                    explanationSection

                    if isLoading {
                        SysStateCard(icon: category.icon,
                                     title: L10n.t("جارٍ تحميل القائمة…", "Loading the list…"),
                                     tint: category.color,
                                     isLoading: true)
                    } else if loadFailed {
                        SysStateCard(icon: "wifi.exclamationmark",
                                     title: L10n.t("تعذّر تحميل القائمة. اسحب للتحديث.",
                                                   "Couldn't load the list. Pull to refresh."),
                                     tint: DS.Color.error,
                                     actionTitle: L10n.t("إعادة المحاولة", "Retry")) {
                            Task {
                                isLoading = true
                                await load()
                            }
                        }
                    } else if members.isEmpty {
                        SysStateCard(icon: "person.crop.circle.badge.checkmark",
                                     title: L10n.t("لا يوجد أحد في هذه الفئة.", "Nobody in this category."),
                                     tint: category.color)
                    } else {
                        membersSection
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .refreshable { await load() }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
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

    private var hero: some View {
        DSPageHero(
            title: category.title,
            subtitle: L10n.t("فئة من «استخدام التطبيق» — الأحياء فقط",
                             "An “App usage” group — living members only"),
            icon: category.icon,
            tint: tint,
            stats: [
                DSHeroStat(value: isLoading ? "—" : "\(members.count)",
                           label: L10n.t("عضو", "Members"), icon: "person.2.fill"),
                DSHeroStat(value: isLoading ? "—" : "\(withPhoneCount)",
                           label: L10n.t("لهم رقم", "With phone"), icon: "phone.fill"),
                DSHeroStat(value: shareText,
                           label: L10n.t("من الأحياء", "Of living"), icon: "chart.pie.fill")
            ]
        )
    }

    // MARK: - لماذا هم هنا؟

    private var explanationSection: some View {
        DSComposerSection(title: L10n.t("لماذا هم هنا؟", "Why are they here?"),
                          icon: "info.circle.fill",
                          tint: tint,
                          index: 1) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: category.icon, tint: category.color)
                    .accessibilityHidden(true)
                Text(category.explanation)
                    .dsFieldFont(12.5, weight: .medium)
                    .foregroundColor(DS.Color.fieldValue)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .dsRowBox()
        }
    }

    // MARK: - الأعضاء

    private var membersSection: some View {
        DSComposerSection(title: L10n.t("الأعضاء", "Members"),
                          icon: "person.2.fill",
                          tint: tint,
                          trailing: "\(members.count)",
                          index: 2) {
            LazyVStack(spacing: 6) {
                ForEach(members) { member in
                    memberRow(member)
                }
            }
        }
    }

    private func memberRow(_ member: AppUsageMember) -> some View {
        let name = member.fullName ?? "—"
        return HStack(spacing: DS.Spacing.sm) {
            initialAvatar(member.fullName)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .dsFieldFont(13.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(2)
                Text(lastSeenText(member))
                    .dsFieldFont(12)
                    .foregroundColor(DS.Color.fieldValue)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            // دعوة سريعة للرجوع للتطبيق — اتصال أو واتساب
            if let phone = member.phone, !phone.isEmpty {
                contactButton(icon: "phone.fill", color: DS.Color.success,
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
        .frame(minHeight: 36)
        .dsRowBox()
    }

    /// الحرف الأول بلون الفئة (بدل صورة — القائمة من السيرفر بلا صور)
    private func initialAvatar(_ name: String?) -> some View {
        let first = (name ?? "").trimmingCharacters(in: .whitespaces).first
        return ZStack {
            Circle().fill(category.color.opacity(0.12))
            if let first {
                Text(String(first))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(category.color)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(category.color)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private func contactButton(icon: String, color: Color, label: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(color.opacity(0.13)))
                .overlay(Circle().strokeBorder(color.opacity(0.25), lineWidth: 1))
                // مساحة ضغط ٤٤ نقطة والشكل كما هو
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .padding(.vertical, -5)
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
