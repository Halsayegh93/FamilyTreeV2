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

struct AppUsageMembersView: View {
    let category: AppUsageCategory
    @Environment(\.openURL) private var openURL

    @State private var members: [AppUsageMember] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    explanationCard

                    if isLoading {
                        ProgressView().tint(category.color).padding(.top, DS.Spacing.xl)
                    } else if loadFailed {
                        Text(L10n.t("تعذّر تحميل القائمة. اسحب للتحديث.", "Couldn't load the list. Pull to refresh."))
                            .font(DS.Font.plex(13, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                            .padding(.top, DS.Spacing.xl)
                    } else if members.isEmpty {
                        Text(L10n.t("لا يوجد أحد في هذه الفئة.", "Nobody in this category."))
                            .font(DS.Font.plex(13, weight: .medium))
                            .foregroundColor(DS.Color.textSecondary)
                            .padding(.top, DS.Spacing.xl)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                                memberRow(member)
                                if index < members.count - 1 {
                                    Divider().padding(.leading, DS.Spacing.lg)
                                }
                            }
                        }
                        .background(DS.Color.surface)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .dsSubtleShadow()
                    }
                }
                .padding(DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .refreshable { await load() }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    private var explanationCard: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            ZStack {
                Circle().fill(category.color.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: category.icon)
                    .font(DS.Font.scaled(16, weight: .bold))
                    .foregroundColor(category.color)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(category.title)
                        .font(DS.Font.plex(15, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer(minLength: 0)
                    if !isLoading {
                        Text("\(members.count)")
                            .font(DS.Font.plex(15, weight: .bold))
                            .foregroundColor(category.color)
                    }
                }
                Text(category.explanation)
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(category.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(category.color.opacity(0.22), lineWidth: 1)
        )
    }

    private func memberRow(_ member: AppUsageMember) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(member.fullName ?? "—")
                    .font(DS.Font.plex(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                Text(lastSeenText(member))
                    .font(DS.Font.plex(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)

            // دعوة سريعة للرجوع للتطبيق — اتصال أو واتساب
            if let phone = member.phone, !phone.isEmpty {
                contactButton(icon: "phone.fill", color: DS.Color.success) {
                    let digits = phone.filter { $0.isNumber || $0 == "+" }
                    if let url = URL(string: "tel:\(digits)") { openURL(url) }
                }
                contactButton(icon: "message.fill", color: Color(hex: "#25D366")) {
                    let digits = phone.filter { $0.isNumber }
                    if let url = URL(string: "https://wa.me/\(digits)") { openURL(url) }
                }
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
    }

    private func contactButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.scaled(13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(color))
        }
        .buttonStyle(DSScaleButtonStyle())
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


