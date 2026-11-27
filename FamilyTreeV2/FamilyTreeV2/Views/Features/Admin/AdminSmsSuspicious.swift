import SwiftUI
import Supabase
import Combine

// MARK: - «محاولة مريبة — شنو اسوي؟» في «طلبات رمز الدخول» (طلب المالك ٢٠٢٦-١١-٢٧ «ما زر ان اسوي شي»)
//
// كان التنبيه يظهر على مربّع «الفريق والأمان» وصفّه، والصفحة لا تعطي إلا نسخ/اتصال في ضغطة مطوّلة — ولا شيء يطفئ التنبيه إلا
// قراءته تحت الجرس. الآن (المنطق الخالص `SmsSuspiciousLogic` في AdminSmsLogic.swift، فحصه S1):
//  • أعلى الصفحة `SmsSuspiciousBanner`: معنى «مريبة» بجملة، وماذا تفعل، و«تم الاطلاع على الكل» = قراءة كل تنبيهات
//    `sms_suspicious` غير المقروءة (ومعها «تقفل رقم» الذي لا رقم فيه) — فتختفي «محاولة مريبة» من المربّع والصفّ.
//  • لكل رقم مريب بطاقة `SmsSuspiciousCard`: الرقم ووقته وعدّاداته (← «تفاصيل الرقم» للمالك، نسخ/اتصال بالضغط المطوّل كما
//    كان)، سطر المعنى، «لمن الرقم؟» (`find_profiles_by_phone` عبر `SmsPhoneOwnerStore` + اسم الشجرة، وحساب الدخول من
//    `last_sign_in_at`)، ثم أزرار ظاهرة ٤٤: «تم الاطلاع» (تنبيهات هذا الرقم — `AdminNoticeWrites.markRead`، نداء
//    «إشعارات الإدارة» نفسه) · «اتصال» (رقم كامل فقط) · «امنع الرقم من التسجيل» (`canManageBannedPhones` × «يعدّل» في
//    `team.registration`، بتأكيد يقول ما سيحدث — نداء «التسجيل والمنع» نفسه `authVM.banPhone`، وبعده تُقرأ تنبيهات الرقم).
//    رقم أحد المالكين لا يُعرض منعه، والممنوع من قبل يُقال ولا يُمنع ثانية.
// لا ترحيل ولا نداء جديد. حارس المكدس: البانر والقسم والبطاقة أنواع مستقلة خلف `AnyView`.

// MARK: - «لمن الرقم؟» — البحث بالرقم (مخزن مشترك)

@MainActor
final class SmsPhoneOwnerStore: ObservableObject {
    static let shared = SmsPhoneOwnerStore()

    /// صفّ `find_profiles_by_phone(p_phone)`: المعرّف والدور والحالة
    nonisolated struct Row: Decodable, Equatable {
        let id: UUID
        let role: String?
        let status: String?
    }

    /// النتائج بالرقم الكامل (`+965…`)
    @Published private(set) var results: [String: [Row]] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var failed: Set<String> = []

    func health(_ e164: String) -> AdminStoreHealth {
        if results[e164] != nil { return failed.contains(e164) ? .failed(lastGood: Date()) : .loaded(at: Date()) }
        if loading.contains(e164) { return .loading }
        return failed.contains(e164) ? .failed(lastGood: nil) : .idle
    }

    /// مرة لكل رقم في الجلسة (إلا بإعادة المحاولة أو السحب للتحديث)
    func lookup(_ e164: String, force: Bool = false) async {
        if !force, results[e164] != nil { return }
        guard !loading.contains(e164) else { return }
        loading.insert(e164)
        defer { loading.remove(e164) }
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .rpc("find_profiles_by_phone", params: ["p_phone": e164.filter(\.isNumber)])
                .execute().value
            results[e164] = rows
            failed.remove(e164)
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            failed.insert(e164)
            Log.warning("[KWT SMS] تعذّر البحث عن صاحب الرقم: \(error.localizedDescription)")
        }
    }
}

// MARK: - الأفعال (تأكيد المنع ونتيجته)

/// ما يُمنع: الرقم الكامل، كما يُعرض، صاحبه (لنصّ التأكيد) وتنبيهاته غير المقروءة (تُقرأ بعد المنع)
struct SmsBanTarget: Identifiable, Equatable {
    let e164: String
    let shown: String
    let owner: SmsSuspiciousLogic.Owner?
    let noticeIds: Set<UUID>
    var id: String { e164 }
}

@MainActor
final class SmsSuspiciousActions: ObservableObject {
    @Published var confirmBan: SmsBanTarget?
    @Published private(set) var banning: Set<String> = []
    @Published var notice: SmsNotice?

    /// «امنع الرقم من التسجيل» بعد التأكيد — نداء «التسجيل والمنع» نفسه، ثم قراءة تنبيهات الرقم
    func ban(_ target: SmsBanTarget, authVM: AuthViewModel, notificationVM: NotificationViewModel) {
        guard !banning.contains(target.e164) else { return }
        banning.insert(target.e164)
        Task {
            defer { banning.remove(target.e164) }
            let ok: Bool
            // تجربة الأدوار: لا كتابة، نجاح مصطنع
            if DebugAdminProbe.dryRun("banned_phones insert \(Log.masked(target.e164))") {
                ok = true
            } else {
                ok = await authVM.banPhone(target.e164, reason: SmsSuspiciousLogic.banReason)
            }
            guard ok else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                notice = SmsNotice(title: L10n.t("لم يُمنع الرقم", "The number wasn't blocked"),
                                   message: L10n.t("تعذّر منع الرقم. قد يكون ممنوعاً بالفعل.",
                                                   "Couldn't block the number. It may already be blocked."))
                return
            }
            await AdminNoticeWrites.markRead(target.noticeIds, notificationVM)
            DSMomentToast.show(L10n.t("مُنع الرقم من التسجيل", "Number blocked"), moment: .success)
        }
    }
}

/// تأكيد المنع ونتيجة الفشل — على الصفحة مرة واحدة
struct SmsSuspiciousAlerts: ViewModifier {
    @ObservedObject var actions: SmsSuspiciousActions
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel

    func body(content: Content) -> some View {
        content
            .dsAlert(L10n.t("منع الرقم من التسجيل؟", "Block this number?"),
                     isPresented: Binding(get: { actions.confirmBan != nil }, set: { if !$0 { actions.confirmBan = nil } }),
                     icon: "phone.down.fill") {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { actions.confirmBan = nil }
                Button(L10n.t("امنع الرقم", "Block number"), role: .destructive) {
                    guard let target = actions.confirmBan else { return }
                    actions.confirmBan = nil
                    actions.ban(target, authVM: authVM, notificationVM: notificationVM)
                }
            } message: {
                if let target = actions.confirmBan {
                    Text(verbatim: SmsSuspiciousLogic.banMessage(phone: target.shown, owner: target.owner))
                }
            }
            .dsAlert(actions.notice?.title ?? "", isPresented: Binding(
                get: { actions.notice != nil },
                set: { if !$0 { actions.notice = nil } }
            ), presenting: actions.notice) { _ in
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { notice in
                Text(notice.message)
            }
    }
}

// MARK: - تنبيهات «محاولات دخول مريبة» كما يقرؤها المنطق

extension NotificationViewModel {
    /// تنبيهات `sms_suspicious` لهذا المستخدم
    var smsSuspiciousNotices: [SmsSuspiciousLogic.Notice] {
        notifications.filter { $0.kind == AdminNotices.smsSuspicious }
            .map { SmsSuspiciousLogic.Notice(id: $0.id, body: $0.body, read: $0.read) }
    }
}

// MARK: - أعلى الصفحة

/// بطاقة الحالة: «محاولات دخول مريبة» + حبّة «3 تنبيهات جديدة» (أو «لا تنبيهات جديدة ✓»)، المعنى بجملة، ماذا تفعل،
/// و«تم الاطلاع على الكل» ما دام غير مقروء
struct SmsSuspiciousBanner: View {
    let suspiciousInPeriod: Int
    @EnvironmentObject private var notificationVM: NotificationViewModel

    var body: some View {
        let notices = notificationVM.smsSuspiciousNotices
        let unread = SmsSuspiciousLogic.unreadIds(notices)
        switch SmsSuspiciousLogic.banner(unread: unread.count, suspiciousInPeriod: suspiciousInPeriod) {
        case .none:
            EmptyView()
        case .unread(let n):
            card(pill: AdminStatePill(title: SmsSuspiciousLogic.unreadWord(n), tone: .error,
                                      icon: "exclamationmark.triangle.fill"),
                 unread: unread)
        case .quiet:
            card(pill: AdminStatePill(title: L10n.t("لا تنبيهات جديدة", "No new alerts"), tone: .ok, icon: "checkmark"),
                 unread: [])
        }
    }

    private func card(pill: AdminStatePill, unread: Set<UUID>) -> some View {
        AdminSectionCard(title: L10n.t("محاولات دخول مريبة", "Suspicious sign-in attempts"), spacing: DS.Spacing.sm,
                         status: pill) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(SmsSuspiciousLogic.pageMeaning)
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SmsSuspiciousLogic.pageAdvice)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !unread.isEmpty {
                DSButton(L10n.t("تم الاطلاع على الكل", "Mark all as seen"), icon: "checkmark.circle") {
                    Task { await AdminNoticeWrites.markRead(unread, notificationVM) }
                }
                .padding(.top, DS.Spacing.xs)
                .accessibilityHint(L10n.t("يقرأ كل تنبيهات المحاولات المريبة فيختفي التنبيه من «الفريق والأمان»",
                                          "Marks every suspicious-attempt alert as read so the alert leaves Team and security"))
            }
        }
    }
}

// MARK: - الأرقام المريبة

/// «أرقام مريبة» ثم بطاقة لكل رقم
struct SmsSuspiciousSection: View {
    let items: [SmsLoginAttempts.Item]
    let days: Int
    @ObservedObject var actions: SmsSuspiciousActions

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Hub.sectionHeadingGap) {
            AdminSectionLabel(title: L10n.t("أرقام مريبة", "Suspicious numbers"),
                              trailing: SmsAttemptsText.period(days))
            VStack(spacing: DS.Hub.cardGap) {
                ForEach(items) { item in
                    AnyView(SmsSuspiciousCard(item: item, days: days, actions: actions))
                }
            }
        }
    }
}

/// بطاقة رقم مريب: الرقم ← سطر المعنى ← «لمن الرقم؟» ← الأزرار (إطار يُرى — بطاقة حالة)
struct SmsSuspiciousCard: View {
    let item: SmsLoginAttempts.Item
    let days: Int
    @ObservedObject var actions: SmsSuspiciousActions
    @ObservedObject private var owners = SmsPhoneOwnerStore.shared
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.adminArea) private var area
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let related = SmsSuspiciousLogic.relatedUnreadIds(notificationVM.smsSuspiciousNotices,
                                                          phoneE164: item.phoneE164, shown: item.phone)
        let owner = resolvedOwner
        let acts = SmsSuspiciousLogic.actions(phoneE164: item.phoneE164, canCall: telURL != nil, canBan: canBan,
                                              isBanned: isBanned, ownersNumber: ownersNumber, relatedUnread: related.count)
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            head
            meaning
            AdminRowDivider()
            ownerBlock(owner)
            buttons(acts, related: related, owner: owner)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .adminCard(framed: true)
        .task(id: item.phoneE164) {
            if let e164 = item.phoneE164 { await owners.lookup(e164) }
        }
    }

    // MARK: ما يقرؤه

    private var canBan: Bool { authVM.canManageBannedPhones && authVM.adminCanEdit(.teamRegistration) }
    private var telURL: URL? { item.phoneE164.flatMap { KuwaitPhone.telURL($0) } }

    private var isBanned: Bool {
        guard let e164 = item.phoneE164 else { return false }
        let key = KuwaitPhone.banKey(e164)
        return authVM.bannedPhones.contains { KuwaitPhone.banKey($0.phoneNumber) == key }
    }

    private var lookupRows: [SmsPhoneOwnerStore.Row] {
        item.phoneE164.flatMap { owners.results[$0] } ?? []
    }

    private var ownersNumber: Bool {
        SmsSuspiciousLogic.isOwnersNumber(matches: lookupRows.map(match))
    }

    /// صاحب الرقم — nil قبل وصول البحث (الرقم الكامل) أو حين تعذّر
    private var resolvedOwner: SmsSuspiciousLogic.Owner? {
        let hasAccount = item.lastSignInAt != nil
        let attemptProfile = item.profileId.map {
            SmsSuspiciousLogic.Match(id: $0, role: memberVM.member(byId: $0)?.role.rawValue, status: item.memberStatus,
                                     name: memberVM.member(byId: $0)?.fullName ?? item.name)
        }
        guard let e164 = item.phoneE164 else {
            // المخفي (لا بحث بالرقم): ملف المحاولة وحده
            return SmsSuspiciousLogic.owner(matches: [], attemptProfile: attemptProfile, hasAccount: hasAccount)
        }
        guard owners.results[e164] != nil else { return nil }
        return SmsSuspiciousLogic.owner(matches: lookupRows.map(match), attemptProfile: attemptProfile, hasAccount: hasAccount)
    }

    private func match(_ row: SmsPhoneOwnerStore.Row) -> SmsSuspiciousLogic.Match {
        let member = memberVM.member(byId: row.id)
        let name = member?.fullName ?? (row.id == item.profileId ? item.name : nil)
        return SmsSuspiciousLogic.Match(id: row.id, role: row.role, status: row.status, name: name)
    }

    // MARK: الرأس: الرقم ووقته وعدّاداته

    private var head: some View {
        Group {
            if let e164 = item.phoneE164 {
                NavigationLink {
                    AdminLazyPage {
                        AnyView(SmsNumberDetailsPage(phoneE164: e164, days: days, name: item.name)
                            .adminArea(area).adminBackTitle(L10n.t("طلبات رمز الدخول", "Sign-in code requests")))
                    }
                } label: { headFace(navigates: true) }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        UIPasteboard.general.string = e164
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    } label: {
                        Label(L10n.t("نسخ الرقم", "Copy number"), systemImage: "doc.on.doc")
                    }
                }
            } else {
                headFace(navigates: false)
            }
        }
    }

    private func headFace(navigates: Bool) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            AdminIconSquare(symbol: "exclamationmark.triangle.fill", tint: DS.Color.error)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: SmsAttemptsText.isolatedLTR(item.phone))
                    .dsFont(.hubValue)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(verbatim: countsLine)
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if navigates { DSChevron().padding(.top, DS.Spacing.xs) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(navigates ? L10n.t("يفتح تفاصيل الرقم", "Opens the number's details") : "")
    }

    /// «قبل 5 دقائق · اليوم 6 · 7 أيام 9 · أعلى ساعة 7»
    private var countsLine: String {
        var parts: [String] = []
        if let when = SmsAttemptsText.relative(item.lastAt) { parts.append(when) }
        if days > 1 { parts.append(L10n.t("اليوم \(item.attemptsToday)", "Today \(item.attemptsToday)")) }
        parts.append("\(SmsAttemptsText.period(days)) \(days == 1 ? item.attemptsToday : item.attemptsInWindow)")
        parts.append(L10n.t("أعلى ساعة \(item.maxInHour)", "Busiest hour \(item.maxInHour)"))
        return parts.joined(separator: " · ")
    }

    // MARK: المعنى

    private var meaning: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
            Image(systemName: "info.circle.fill")
                .dsGlyph(DS.Glyph.sm, weight: .semibold)
                .foregroundColor(DS.Color.error)
                .accessibilityHidden(true)
            Text(SmsSuspiciousLogic.meaningLine)
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: لمن الرقم؟

    @ViewBuilder private func ownerBlock(_ owner: SmsSuspiciousLogic.Owner?) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(L10n.t("لمن الرقم؟", "Whose number is it?"))
                .dsFont(.subtitle)
                .foregroundColor(DS.Color.textTertiary)
            if let owner {
                ownerFace(owner)
            } else if let e164 = item.phoneE164, owners.health(e164).canRetry {
                Button { Task { await owners.lookup(e164, force: true) } } label: {
                    Label(L10n.t("تعذّر معرفة صاحب الرقم — أعد المحاولة", "Couldn't find the owner — retry"),
                          systemImage: "arrow.clockwise")
                        .dsFont(.body)
                        .foregroundColor(DS.Color.primary)
                        .frame(minHeight: DS.Icon.tapTarget)
                }
                .buttonStyle(DSPressStyle())
            } else {
                Text(verbatim: AdminStoreHealthText.placeholder)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityLabel(L10n.t("جارٍ البحث عن صاحب الرقم", "Looking up the owner"))
            }
        }
    }

    @ViewBuilder private func ownerFace(_ owner: SmsSuspiciousLogic.Owner) -> some View {
        let title = SmsSuspiciousLogic.ownerTitle(owner)
        let detail = SmsSuspiciousLogic.ownerDetail(owner)
        let face = VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            if case .member = owner {
                Text(verbatim: PersonName.threeParts(title))
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .dsNameLines()
            } else {
                Text(verbatim: title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail {
                Text(verbatim: detail)
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // العضو المعروف في الشجرة: ملفه بضغطة
        if case .member = owner, let member = ownerMember {
            NavigationLink { AdminLazyPage { AnyView(AdminMemberDetailSheet(member: member)) } } label: {
                HStack(spacing: DS.Spacing.sm) {
                    face
                    Spacer(minLength: 0)
                    DSChevron()
                }
                .frame(minHeight: DS.Icon.tapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(AdminRowPressStyle())
            .accessibilityHint(L10n.t("يفتح ملف العضو", "Opens the member's profile"))
        } else {
            face.accessibilityElement(children: .combine)
        }
    }

    /// الملف المعروض اسمه (أول ملف باسم بين النتائج وملف المحاولة) — لفتحه
    private var ownerMember: FamilyMember? {
        let ids = lookupRows.map(\.id) + [item.profileId].compactMap { $0 }
        return ids.lazy.compactMap { memberVM.member(byId: $0) }.first { !$0.fullName.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: الأزرار

    @ViewBuilder
    private func buttons(_ acts: SmsSuspiciousLogic.Actions, related: Set<UUID>,
                         owner: SmsSuspiciousLogic.Owner?) -> some View {
        let states = statePills(acts)
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if !states.isEmpty {
                OccasionFlowLayout(spacing: DS.Spacing.xs) {
                    ForEach(states, id: \.title) { pill in pill }
                }
            }
            let seen = seenButton(acts, related: related)
            let call = callButton(acts)
            if seen != nil || call != nil {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: DS.Spacing.sm) { seen; call }
                } else {
                    HStack(spacing: DS.Spacing.sm) { seen; call }
                }
            }
            if acts.ban == .available, let e164 = item.phoneE164 {
                DSButton(L10n.t("امنع الرقم من التسجيل", "Block from signing up"), icon: "phone.down.fill",
                         role: .destructive, isLoading: actions.banning.contains(e164)) {
                    actions.confirmBan = SmsBanTarget(e164: e164, shown: item.phone, owner: owner, noticeIds: related)
                }
                .accessibilityHint(L10n.t("يسأل أولاً، ثم لا يستطيع صاحب الرقم التسجيل أو الدخول",
                                          "Asks first; then the number can't sign up or sign in"))
            }
        }
    }

    /// «تم الاطلاع ✓» و«ممنوع من التسجيل» حين انتهى أمرهما
    private func statePills(_ acts: SmsSuspiciousLogic.Actions) -> [AdminStatePill] {
        var pills: [AdminStatePill] = []
        if acts.seen == .done {
            pills.append(AdminStatePill(title: L10n.t("تم الاطلاع", "Seen"), tone: .ok, icon: "checkmark"))
        }
        if acts.ban == .alreadyBanned {
            pills.append(AdminStatePill(title: L10n.t("ممنوع من التسجيل", "Blocked from signing up"), tone: .error,
                                        icon: "phone.down.fill"))
        }
        return pills
    }

    /// «تم الاطلاع» — يقرأ تنبيهات هذا الرقم وحده
    private func seenButton(_ acts: SmsSuspiciousLogic.Actions, related: Set<UUID>) -> DSButton? {
        guard case .button = acts.seen else { return nil }
        return DSButton(L10n.t("تم الاطلاع", "Seen"), icon: "checkmark") {
            Task { await AdminNoticeWrites.markRead(related, notificationVM) }
        }
    }

    /// «اتصال» — الرقم الكامل فقط
    private func callButton(_ acts: SmsSuspiciousLogic.Actions) -> DSButton? {
        guard acts.call, let url = telURL else { return nil }
        return DSButton(L10n.t("اتصال", "Call"), icon: "phone.fill", role: .cancel) { openURL(url) }
    }
}
