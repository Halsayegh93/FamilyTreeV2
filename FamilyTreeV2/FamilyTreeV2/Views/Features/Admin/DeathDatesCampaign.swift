import SwiftUI
import Supabase
import Combine

// MARK: - «إدارة تواريخ الوفاة» — حملة استكمال التواريخ (طلب المالك ٢٠٢٦-١٠-٢٤)
//
// «ابى قسم بالادارة لادارة تواريخ الوفاة يكون بارز بلوحة الادارة يكون لفترة معينة بعدين نشيله نحط مكانه قسم ذكرى
// المتوفين بعد ما نحصل التواريخ الى ما نحصله نخلي مكانه لا يوجد تاريخ كامل للوفاة».
// • التخزين (السيرفر الحي): `profiles.death_date` (date) — السنة وحدها محفوظة YYYY-01-01، والسنة < 1700 هجري مكتوب
//   كميلادي، و`death_date_unknown` = «التاريخ غير معروف» (قرار إداري: لا يُطلب). التصنيف الواحد `DeceasedMemorial.classify`
//   (نفس الأندرويد والموقع)، والنطاق نطاق «ذكرى الراحلين»: متوفو الشجرة المعدودون (`isCountable`).
// • الاستكمال بالمسار الموجود `DeceasedDateBox` (عجلة اليوم والشهر والسنة ← `updateMemberHealthAndBirth`، بلا إشعار لكل
//   تاريخ). «من أكمل ومتى» من `profiles.updated_by/updated_at` اللذين يضعهما المسار نفسه — قراءة فقط، بلا دالة جديدة.
// • المدة من السيرفر (`app_config`): `death_dates_campaign` (إبرازها في «اليوم») و`death_dates_campaign_until` (آخر يوم،
//   فارغ = حتى تكتمل). قبل إضافة المفتاحين (ترحيل ينتظر موافقة المالك) تظهر ما دام في التواريخ ناقص. المالك يوقفها أو يحدّد
//   آخر يوم من صفحتها (`set_app_config` الموجودة، للمالك فقط).
// • بعدها (موقوفة، انتهت، أو اكتملت التواريخ) المكان نفسه في «اليوم» «ذكرى الراحلين»، ومن بقي بلا تاريخ كامل يُذكر فيه بـ
//   «لا يوجد تاريخ كامل للوفاة».

/// أرقام التواريخ: كل متوفى معدود في واحدة من أربع
struct DeathDatesStats: Equatable {
    /// اليوم والشهر والسنة
    var full = 0
    /// السنة فقط (أو سنة هجرية مكتوبة كميلادية)
    var yearOnly = 0
    /// بلا تاريخ
    var missing = 0
    /// «التاريخ غير معروف» — قرار إداري، لا يُطلب ولا يُعدّ ناقصاً
    var unknown = 0

    var total: Int { full + yearOnly + missing + unknown }
    /// ما يحتاج استكمالاً
    var incomplete: Int { yearOnly + missing }
    /// المكتمل من المطلوب (بلا «غير معروف») — nil = لا متوفين بعد
    var share: Double? {
        let need = full + incomplete
        return need > 0 ? Double(full) / Double(need) : nil
    }
    var percent: Int? { DSGaugeText.share(full, of: full + incomplete) }
}

/// متوفى تاريخ وفاته غير كامل — صفّ في صفحة الحملة
struct DeathDatesEntry: Identifiable {
    let member: FamilyMember
    let kind: DeceasedMemorial.DateKind
    /// رأس الفرع (ابن مباشر لرأس الشجرة) — nil = خارج الفروع
    let branch: UUID?
    /// الاسم مُطبَّعاً للبحث
    let needle: String
    var id: UUID { member.id }

    /// العقد من السنة المعروفة (١٩٩٠ لسنة ١٩٩٥) — nil = بلا سنة أو هجري
    var decade: Int? {
        if case .yearOnly(let y) = kind { return y / 10 * 10 }
        return nil
    }

    var isMissing: Bool { kind == .missing }

    /// سنة الميلاد إن عُرفت (تساعد على تمييز الاسم)
    var birthYear: Int? {
        guard let raw = member.birthDate?.trimmingCharacters(in: .whitespacesAndNewlines), raw.count >= 4,
              let y = Int(raw.prefix(4)), y >= DeceasedMemorial.minGregorianYear else { return nil }
        return y
    }
}

enum DeathDatesCampaign {
    /// نص المالك نفسه لمن لا تاريخ كامل له (في «ذكرى الراحلين» وقوائم المناسبات)
    static var noFullDate: String { L10n.t("لا يوجد تاريخ كامل للوفاة", "No full date of death") }

    /// نطاق «ذكرى الراحلين» نفسه
    static func isCounted(_ m: FamilyMember) -> Bool { m.isDeceased == true && m.isCountable }

    static func stats(_ all: [FamilyMember]) -> DeathDatesStats {
        var s = DeathDatesStats()
        for m in all where isCounted(m) {
            if m.deathDateUnknown == true { s.unknown += 1; continue }
            switch DeceasedMemorial.classify(m.deathDate) {
            case .exact: s.full += 1
            case .yearOnly, .hijriLike: s.yearOnly += 1
            case .missing: s.missing += 1
            }
        }
        return s
    }

    /// من يحتاج استكمالاً — الهجري ثم «السنة فقط» الأحدث أولاً ثم بلا تاريخ، وبالاسم داخلها
    static func entries(_ all: [FamilyMember]) -> [DeathDatesEntry] {
        let heads = AdminMembersIndex.branchHeads(all)
        var list: [DeathDatesEntry] = []
        for m in all where isCounted(m) && m.deathDateUnknown != true {
            let kind = DeceasedMemorial.classify(m.deathDate)
            if case .exact = kind { continue }
            list.append(DeathDatesEntry(member: m, kind: kind, branch: heads[m.id],
                                        needle: ArabicTextNormalizer.normalizeForSearch(m.fullName)))
        }
        return list.sorted {
            let a = DeceasedMemorial.missingRank($0.kind), b = DeceasedMemorial.missingRank($1.kind)
            if a != b { return a < b }
            return $0.member.fullName.localizedStandardCompare($1.member.fullName) == .orderedAscending
        }
    }

    /// «السنة فقط: 1995» / «مكتوب بالهجري: 1418» / «بدون تاريخ» (نفس ورقة العضو)
    static func note(_ kind: DeceasedMemorial.DateKind) -> String {
        DeceasedMemorial.missingNote(kind, arabic: L10n.isArabic)
    }

    /// لون الحال: السنة فقط كهرماني، بلا تاريخ رمادي المتوفين
    static func tint(_ kind: DeceasedMemorial.DateKind) -> Color {
        kind == .missing ? DS.Color.deceased : DS.Color.warning
    }
}

// MARK: - المخزن: مدة الحملة من السيرفر، و«أُكملت مؤخراً»

/// تاريخ اكتمل — من أكمله ومتى (`profiles.updated_by/updated_at`)
struct DeathDatesCompletion: Identifiable, Equatable {
    let id: UUID
    let by: UUID?
    let at: Date?
}

@MainActor
final class DeathDatesCampaignStore: ObservableObject {
    static let shared = DeathDatesCampaignStore()

    static let enabledKey = "death_dates_campaign"
    static let untilKey = "death_dates_campaign_until"
    /// «أُكملت مؤخراً»: آخر ٣٠ يوماً
    static let recentDays = 30

    /// إبرازها في «اليوم» — nil = المفتاح ليس على السيرفر بعد أو لم يُقرأ (تظهر ما دام في التواريخ ناقص)
    @Published private(set) var enabled: Bool?
    /// آخر يوم للحملة (شاملاً) — nil = حتى تكتمل
    @Published private(set) var until: Date?
    /// المفتاحان على السيرفر — يُعدّلان من الصفحة (للمالك)
    @Published private(set) var serverReady = false
    @Published private(set) var loadedAt: Date?
    /// آخر من اكتمل تاريخه (الأحدث أولاً)
    @Published var recent: [DeathDatesCompletion] = []
    @Published private(set) var isSaving = false

    /// تظهر الحملة الآن: ما دام في التواريخ ناقص، وغير موقوفة، ولم يمضِ آخر يوم
    func isActive(_ stats: DeathDatesStats, today: Date = Date()) -> Bool {
        guard stats.incomplete > 0, enabled != false else { return false }
        if let until, Self.calendar.startOfDay(for: today) > until { return false }
        return true
    }

    /// يقرأ المفتاحين من `app_config()` (القيم لكل الإدارة) — مرة كل ٥ دقائق ما لم يُطلب
    func refresh(force: Bool = false) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 300 { return }
        do {
            let data = try await SupabaseConfig.client.rpc("app_config").execute().data
            apply(data)
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[DEATH DATES] تعذّر جلب مدة الحملة: \(error.localizedDescription)")
        }
    }

    /// `{values: {…}}` أو القيم في الجذر — مفتاح غائب = لم يُضَف على السيرفر بعد
    func apply(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let values = root["values"] as? [String: Any] ?? root
        let flag = values[Self.enabledKey]
        enabled = (flag as? NSNumber)?.boolValue
        until = (values[Self.untilKey] as? String).flatMap(Self.day)
        serverReady = flag != nil
        loadedAt = Date()
    }

    /// «أُكملت مؤخراً»: من عُدّل من المتوفين خلال ٣٠ يوماً (الصفحة تُبقي من صار تاريخه كاملاً)
    func refreshRecent() async {
        struct Row: Decodable {
            let id: UUID
            let updated_by: UUID?
            let updated_at: String?
        }
        guard let since = Self.calendar.date(byAdding: .day, value: -Self.recentDays, to: Date()) else { return }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("profiles")
                .select("id, updated_by, updated_at")
                .eq("is_deceased", value: true)
                .gte("updated_at", value: iso.string(from: since))
                .order("updated_at", ascending: false)
                .limit(60)
                .execute()
                .value
            recent = rows.map { DeathDatesCompletion(id: $0.id, by: $0.updated_by, at: AdminDeviceReachStore.date($0.updated_at)) }
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[DEATH DATES] تعذّر جلب من أكمل التواريخ: \(error.localizedDescription)")
        }
    }

    // MARK: الحفظ (المالك — `set_app_config`)

    private struct BoolParams: Encodable {
        let p_key: String
        let p_value: Bool
    }

    private struct TextParams: Encodable {
        let p_key: String
        let p_value: String
    }

    /// يوقف الحملة أو يعيدها — nil = نجح، وإلا رسالة الخطأ
    func save(enabled value: Bool) async -> String? {
        await save { try await SupabaseConfig.client.rpc("set_app_config", params: BoolParams(p_key: Self.enabledKey, p_value: value)).execute() } then: {
            self.enabled = value
        }
    }

    /// آخر يوم — nil = حتى تكتمل التواريخ
    func save(until value: Date?) async -> String? {
        let text = value.map { SmsJSON.dayKey.string(from: $0) } ?? ""
        return await save { try await SupabaseConfig.client.rpc("set_app_config", params: TextParams(p_key: Self.untilKey, p_value: text)).execute() } then: {
            self.until = value.map { Self.calendar.startOfDay(for: $0) }
        }
    }

    private func save(_ call: () async throws -> PostgrestResponse<Void>, then done: () -> Void) async -> String? {
        guard !isSaving else { return nil }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await call()
            done()
            return nil
        } catch {
            if ErrorHelper.isCancellation(error) { return nil }
            Log.warning("[DEATH DATES] تعذّر حفظ إعداد الحملة: \(error.localizedDescription)")
            guard let pg = error as? PostgrestError else {
                return L10n.t("تعذّر الحفظ — تأكد من الاتصال وجرّب مرة ثانية.", "Couldn't save — check the connection and retry.")
            }
            switch pg.hint {
            case "unknown_key":
                return L10n.t("مفتاح الحملة غير موجود في السيرفر بعد — يحتاج تحديث السيرفر.",
                              "The campaign setting isn't on the server yet — it needs a server update.")
            case "bad_value":
                return pg.message.isEmpty ? L10n.t("القيمة غير مقبولة.", "Value not accepted.") : pg.message
            default:
                if pg.code == "42501" || pg.hint == "not_allowed" {
                    return L10n.t("إعداد الحملة للمالك فقط.", "Only the owner can change the campaign.")
                }
                return L10n.t("تعذّر الحفظ — جرّب مرة ثانية.", "Couldn't save — try again.")
            }
        }
    }

    // MARK: التاريخ

    /// التقويم الميلادي بتوقيت الكويت (نفس `SmsJSON.dayKey`)
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = SmsJSON.kuwait
        return c
    }

    /// «2026-11-30» ← بداية ذلك اليوم — فارغ أو غير صالح = nil
    static func day(_ raw: String) -> Date? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 10, let date = SmsJSON.dayKey.date(from: String(text.prefix(10))) else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// «حتى ٣٠ نوفمبر» بأرقام لاتينية مثل باقي التواريخ
    static func untilText(_ date: Date) -> String {
        let c = calendar.dateComponents([.day, .month, .year], from: date)
        let dayMonth = DeceasedMemorial.dayMonth(day: c.day ?? 1, month: c.month ?? 1, arabic: L10n.isArabic)
        let sameYear = c.year == calendar.component(.year, from: Date())
        return sameYear ? dayMonth : "\(dayMonth) \(c.year ?? 0)"
    }
}
