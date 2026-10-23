import SwiftUI
import Supabase
import Combine

// MARK: - «حماية رسائل الدخول» في صفحة «إعدادات الإرسال» (السيرفر الحي ٢٠٢٦-١٠-٢٢)
//
// خمسة مفاتيح من `app_config` (السيرفر يطبّقها على كل طلب رمز): رمز واحد ما دام الأول صالحاً، أقصى رسائل للرقم باليوم،
// وقفل الرقم بعد عدد طلبات خلال دقائق لمدة محددة. القراءة: `app_config()` (`{values, meta, can_edit…}` — فكّ متسامح:
// القيم في `values` أو في الجذر، والمدى من `meta.min/max` إن وُجد وإلا مدى ثابت هنا). الحفظ: `set_app_config(p_key, p_value)`
// للمالك فقط (غيره 42501)، كل مفتاح وحده بعد توقّف الضغط؛ الأخطاء بـ `hint` (`bad_value` نص السيرفر، `unknown_key`).
// المدير يقرأ فقط. البطاقة نوع مستقل خلف `AnyView` (حارس المكدس). «فك القفل» لرقم في «تفاصيل الرقم».

/// مفتاح واحد من «حماية رسائل الدخول»
struct SmsGuardKey: Identifiable, Equatable {
    let id: String
    let icon: String
    let title: String
    var note: String? = nil
    /// المدى الاحتياطي (السيرفر قد يرسل غيره في `meta`)
    let range: ClosedRange<Int>
    let ladder: [Int]
    let unit: ApprovalHoursStepper.Unit
    /// القيمة مخزّنة بالثواني وتُعرض بالدقائق
    var storedInSeconds = false

    static let all: [SmsGuardKey] = [
        SmsGuardKey(id: "sms_one_code_seconds", icon: "key.fill",
                    title: L10n.t("رمز واحد لكل", "One code per"),
                    note: L10n.t("ما يوصله رمز ثاني ما دام الأول صالح", "No second code while the first one is still valid"),
                    range: 0...900, ladder: [0, 60, 120, 180, 300, 600, 900], unit: .minutes, storedInSeconds: true),
        SmsGuardKey(id: "sms_daily_per_number", icon: "calendar",
                    title: L10n.t("أقصى رسائل للرقم باليوم", "Max messages per number per day"),
                    range: 1...50, ladder: [1, 2, 3, 4, 5, 7, 10, 15, 20, 30, 50], unit: .count),
        SmsGuardKey(id: "sms_lock_requests", icon: "lock.fill",
                    title: L10n.t("قفل الرقم بعد (طلبات)", "Lock the number after (requests)"),
                    range: 3...30, ladder: [3, 4, 5, 6, 8, 10, 15, 20, 30], unit: .count),
        SmsGuardKey(id: "sms_lock_window_minutes", icon: "timer",
                    title: L10n.t("خلال (دقائق)", "Within (minutes)"),
                    range: 1...60, ladder: [1, 2, 3, 5, 10, 15, 20, 30, 45, 60], unit: .minutes),
        SmsGuardKey(id: "sms_lock_minutes", icon: "hourglass",
                    title: L10n.t("مدة القفل (دقائق)", "Lock duration (minutes)"),
                    range: 5...1440, ladder: [5, 10, 15, 30, 60, 120, 180, 360, 720, 1440], unit: .minutes)
    ]

    /// القيمة كما تُعرض (دقائق للمخزّن بالثواني)
    func shown(_ stored: Int) -> Int { storedInSeconds ? stored / 60 : stored }
    func stored(_ shown: Int) -> Int { storedInSeconds ? shown * 60 : shown }
}

// MARK: - المخزن

@MainActor
final class SmsLoginGuardStore: ObservableObject {
    static let shared = SmsLoginGuardStore()

    enum LoadState: Equatable { case idle, loading, loaded, failed }

    /// القيم المحفوظة على السيرفر (بوحدة السيرفر)
    @Published private(set) var values: [String: Int] = [:]
    /// المدى من `meta` إن أرسله السيرفر
    @Published private(set) var ranges: [String: ClosedRange<Int>] = [:]
    /// `can_edit` من السيرفر (nil = لم يذكره)
    @Published private(set) var canEdit: Bool?
    @Published private(set) var state: LoadState = .idle

    func refresh() async {
        guard state != .loading else { return }
        if values.isEmpty { state = .loading }
        do {
            let data = try await SupabaseConfig.client.rpc("app_config").execute().data
            apply(data)
            state = .loaded
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            Log.warning("[KWT SMS] تعذّر جلب حماية رسائل الدخول: \(error.localizedDescription)")
            if values.isEmpty { state = .failed } else { state = .loaded }
        }
    }

    private func apply(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let source = root["values"] as? [String: Any] ?? root
        let meta = root["meta"] as? [String: Any] ?? [:]
        var nextValues: [String: Int] = [:]
        var nextRanges: [String: ClosedRange<Int>] = [:]
        for key in SmsGuardKey.all {
            if let v = SmsJSON.int(source[key.id]) { nextValues[key.id] = v }
            if let m = meta[key.id] as? [String: Any],
               let lo = SmsJSON.int(m["min"] ?? m["min_value"]), let hi = SmsJSON.int(m["max"] ?? m["max_value"]), lo <= hi {
                nextRanges[key.id] = lo...hi
            }
        }
        values = nextValues
        ranges = nextRanges
        canEdit = root["can_edit"] as? Bool
    }

    private struct SetParams: Encodable {
        let p_key: String
        let p_value: Int
    }

    /// يحفظ مفتاحاً واحداً — nil = نجح، وإلا رسالة الخطأ بالعربي
    func save(_ key: String, _ value: Int) async -> String? {
        do {
            let data = try await SupabaseConfig.client
                .rpc("set_app_config", params: SetParams(p_key: key, p_value: value))
                .execute().data
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            values[key] = SmsJSON.int(root?["value"]) ?? value
            return nil
        } catch {
            if ErrorHelper.isCancellation(error) { return nil }
            Log.warning("[KWT SMS] تعذّر حفظ \(key): \(error.localizedDescription)")
            guard let pg = error as? PostgrestError else {
                return L10n.t("تعذّر الحفظ — تأكد من الاتصال وجرّب مرة ثانية.", "Couldn't save — check the connection and retry.")
            }
            switch pg.hint {
            case "bad_value":
                return pg.message.isEmpty ? L10n.t("القيمة غير مقبولة.", "Value not accepted.") : pg.message
            case "unknown_key":
                Task { await refresh() }
                return L10n.t("هذا الإعداد غير موجود في السيرفر.", "This setting doesn't exist on the server.")
            default:
                if pg.code == "42501" || pg.hint == "not_allowed" {
                    return L10n.t("تعديل الحماية للمالك فقط.", "Only the owner can change the protection.")
                }
                return L10n.t("تعذّر الحفظ — جرّب مرة ثانية.", "Couldn't save — try again.")
            }
        }
    }
}

// MARK: - البطاقة

struct SmsLoginGuardCard: View {
    @ObservedObject private var store = SmsLoginGuardStore.shared
    @EnvironmentObject var authVM: AuthViewModel
    /// تعديل المالك قبل الحفظ (بوحدة السيرفر) ورقم آخر ضغطة لكل مفتاح
    @State private var drafts: [String: Int] = [:]
    @State private var generations: [String: Int] = [:]
    @State private var errors: [String: String] = [:]

    var body: some View {
        let canEdit = authVM.isOwner && store.canEdit != false && store.state == .loaded
        let keys = SmsGuardKey.all.filter { store.values[$0.id] != nil }
        AdminRowsCard(title: L10n.t("حماية رسائل الدخول", "Sign-in message protection"),
                      footnote: footnote(canEdit: canEdit, empty: keys.isEmpty)) {
            if store.state == .loaded || !store.values.isEmpty {
                if keys.isEmpty {
                    DSNoteCard(L10n.t("السيرفر لم يرسل هذه الإعدادات بعد.", "The server hasn't sent these settings yet."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                }
                ForEach(keys) { key in
                    row(key, canEdit: canEdit)
                }
            } else if store.state == .failed {
                DSNoteCard(L10n.t("تعذّر جلب الحماية الآن — اسحب للتحديث.", "Couldn't load the protection — pull to refresh."),
                           icon: "wifi.exclamationmark", tint: DS.Color.warning)
            } else {
                DSPageLoader(L10n.t("جاري جلب الحماية…", "Loading protection…"),
                             size: DS.Icon.loaderArtInline, fillsSpace: false)
            }
        }
        .task { await store.refresh() }
    }

    private func footnote(canEdit: Bool, empty: Bool) -> String? {
        guard store.state == .loaded, !empty else { return nil }
        return canEdit ? L10n.t("تُحفظ تلقائياً وتسري على الطلب التالي.", "Saved automatically; applies to the next request.")
                       : AdminPageHeader.readOnlyText
    }

    @ViewBuilder
    private func row(_ key: SmsGuardKey, canEdit: Bool) -> some View {
        let stored = drafts[key.id] ?? store.values[key.id] ?? key.range.lowerBound
        let range = store.ranges[key.id] ?? key.range
        let shownRange = key.shown(range.lowerBound)...key.shown(range.upperBound)
        VStack(alignment: .leading, spacing: 0) {
            if canEdit {
                SmsKVRow(icon: key.icon, label: key.title, note: key.note, tint: DS.Color.primary, combines: false) {
                    ApprovalHoursStepper(value: key.shown(stored), range: shownRange, step: 1, label: key.title,
                                         onChange: { save(key, key.stored($0)) }, unit: key.unit,
                                         ladder: key.ladder.map(key.shown),
                                         zeroText: key.storedInSeconds ? L10n.t("مطفأ", "Off") : nil)
                }
            } else {
                SmsKVRow(icon: key.icon, label: key.title, value: readText(key, stored), note: key.note, tint: DS.Color.primary)
            }
            if let error = errors[key.id] {
                Text(error)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, DS.Icon.section + DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.sm)
            }
        }
    }

    /// نص القراءة للمدير
    private func readText(_ key: SmsGuardKey, _ stored: Int) -> String {
        if key.storedInSeconds {
            if stored == 0 { return L10n.t("مطفأ", "Off") }
            if stored % 60 != 0 { return L10n.t("\(stored) ثانية", "\(stored) s") }
        }
        let v = key.shown(stored)
        switch key.unit {
        case .minutes:
            if v >= 60, v % 60 == 0 { return L10n.t("\(v / 60) ساعة", "\(v / 60) h") }
            return L10n.t("\(v) دقيقة", "\(v) min")
        default:
            return "\(v)"
        }
    }

    /// يظهر فوراً، ويُحفظ بعد توقّف الضغط ثلثي ثانية — كل مفتاح وحده؛ الفشل يرجع القيمة المحفوظة ويظهر الخطأ تحت الصفّ
    private func save(_ key: SmsGuardKey, _ value: Int) {
        drafts[key.id] = value
        errors[key.id] = nil
        let mine = (generations[key.id] ?? 0) + 1
        generations[key.id] = mine
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard generations[key.id] == mine else { return }
            let error = await store.save(key.id, value)
            guard generations[key.id] == mine else { return }
            drafts[key.id] = nil
            errors[key.id] = error
        }
    }
}
