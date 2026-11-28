import SwiftUI
import Combine
import Supabase

// MARK: - «طلب استكمال البيانات» (المالك ٢٠٢٦-١١-٢٧، الوحدة R2 — ترحيل 20261127180000)
//
// الإدارة (مربّع البيانات في «الوارد») تحدّد الناقص وتكتب ملاحظة ← `ask_join_completion` ← إشعار رسمي للعضو، والطلب يبقى
// معلّقاً. العضو:
//  • طلب الانضمام المعلّق: بطاقة في مربّع «قيد المراجعة» ← «استكمال البيانات» ← مربّع التسجيل نفسه بالحقول المطلوبة مميّزة
//    (والصورة إن طُلبت) ← الحفظ كما «تعديل الطلب» ← `answer_completion_ask` (السيرفر يتحقق أن المطلوب صار في ملفه).
//  • «استكمال التسجيل» المعلّق: بوابة «أكمل حسابك» تُفتح بحقل «اسم الوالدة» مميّزاً ← `answer_completion_ask({mother_name})`
//    يكتب الاسم في طلب النسب المعلّق نفسه.
// الحقول والنصوص: `AdminJoinBoxRules` (MissingField، askMessage، signupHighlights).

enum CompletionAsk {
    nonisolated struct Open: Decodable, Equatable, Sendable {
        let requestId: UUID
        let kind: String
        let fields: [String]
        let note: String?
        enum CodingKeys: String, CodingKey { case requestId = "request_id", kind, fields, note }

        var isLineage: Bool { kind == "lineage" }
        /// طلب ربط الزوج/الزوجة (20261128150000): «اسم الزوج أو الزوجة» يُصحَّح من «استكمال التسجيل»
        var isSpouse: Bool { kind == "spouse" }
        /// طلب انضمام معلّق — بطاقته في «قيد المراجعة»
        var isJoin: Bool { !isLineage && !isSpouse }
        var missing: [AdminJoinBoxRules.MissingField] { AdminJoinBoxRules.parseFields(fields) }
    }

    /// الإدارة: يُرسل للعضو (الطلب يبقى معلّقاً)
    static func ask(requestId: UUID, fields: Set<AdminJoinBoxRules.MissingField>, note: String) async throws {
        let n = note.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let params: [String: AnyEncodable] = [
            "p_request_id": AnyEncodable(requestId.uuidString),
            "p_fields": AnyEncodable(AdminJoinBoxRules.orderedKeys(fields)),
            "p_note": AnyEncodable(n.isEmpty ? nil : n)
        ]
        _ = try await SupabaseConfig.client.rpc("ask_join_completion", params: params).execute()
    }

    /// العضو: الطلب المفتوح — nil = لا طلب (أو الدالة غائبة قبل الترحيل)
    static func mine() async -> Open? {
        do {
            let data = try await SupabaseConfig.client.rpc("my_completion_ask").execute().data
            guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty, text != "null" else { return nil }
            return try JSONDecoder().decode(Open.self, from: data)
        } catch {
            if !ErrorHelper.isCancellation(error) { Log.warning("[CompletionAsk] my_completion_ask: \(error.localizedDescription)") }
            return nil
        }
    }

    static func answer(_ values: [String: String]) async throws {
        _ = try await SupabaseConfig.client.rpc("answer_completion_ask", params: ["p_values": values]).execute()
    }

    /// رسائل رسمية بالـ hint
    static func message(_ error: Error) -> String {
        let pg = error as? PostgrestError
        switch pg?.hint ?? "" {
        case "not_allowed": return L10n.t("ليست لديك صلاحية لهذا الإجراء.", "You don't have permission for this.")
        case "request_not_found", "already_handled":
            return L10n.t("تمت معالجة هذا الطلب مسبقاً.", "This request was already handled.")
        case "fields_required": return L10n.t(AdminJoinBoxRules.Ar.mustTickOne, "Tick at least one item.")
        case "note_too_long": return L10n.t("الملاحظة طويلة — ٢٠٠ حرف على الأكثر.", "The note is too long — 200 characters at most.")
        case "bad_field": return L10n.t("أحد الحقول غير متاح لهذا الطلب.", "One of the items isn't available for this request.")
        case "no_ask": return L10n.t("لا يوجد طلب استكمال مفتوح.", "There's no open request for details.")
        case "name_required": return L10n.t(AdminJoinBoxRules.Ar.motherNameRequired, "Type your mother's four-part name.")
        case "name_too_long": return L10n.t("الاسم طويل.", "The name is too long.")
        case "missing_value": return pg?.message ?? L10n.t("يُرجى إدخال البيانات المطلوبة.", "Enter the requested details.")
        default:
            if pg?.code == "PGRST202" {
                return L10n.t("هذه الخدمة غير متاحة بعد على الخادم.", "This service isn't available on the server yet.")
            }
            return L10n.t("تعذّر الإرسال. يُرجى المحاولة مرة أخرى.", "Couldn't send. Please try again.")
        }
    }
}

/// طلب الاستكمال المفتوح للعضو — تقرؤه شاشة «قيد المراجعة» ومربّع التسجيل
@MainActor
final class CompletionAskStore: ObservableObject {
    static let shared = CompletionAskStore()
    @Published private(set) var open: CompletionAsk.Open?
    /// فُتح مربّع التسجيل من «استكمال البيانات»
    @Published var editing = false
    /// فشل إغلاق الطلب بعد الحفظ (يظهر في البطاقة)
    @Published var answerError: String?

    func refresh() async {
        let next = await CompletionAsk.mine()
        if next != open { open = next }
    }

    /// بعد حفظ مربّع التسجيل: يُغلق الطلب على السيرفر (يتحقق أن المطلوب صار في الملف)
    func answerAfterSignup() async {
        guard editing else { return }
        editing = false
        do {
            try await CompletionAsk.answer([:])
            answerError = nil
            open = nil
        } catch {
            answerError = CompletionAsk.message(error)
        }
        await refresh()
    }

    func clear() { open = nil }
}

/// بطاقة «يُرجى استكمال البيانات» في مربّع «قيد المراجعة» (طلب انضمام معلّق)
struct CompletionAskCard: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = CompletionAskStore.shared
    private typealias T = AdminJoinBoxRules.Ar

    var body: some View {
        Group {
            if let open = store.open, open.isJoin {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Label(L10n.t(T.memberAskTitle, "Please complete your details"), systemImage: "exclamationmark.circle.fill")
                        .dsFont(.rowTitle).foregroundColor(DS.Color.warning)
                    Text(L10n.t(T.memberAskBody, "The admins asked you to complete:"))
                        .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    Text(verbatim: open.missing.map { AdminJoinBoxRules.fieldLabel($0) }.joined(separator: "، "))
                        .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note = open.note, !note.isEmpty {
                        Text(verbatim: note).dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let e = store.answerError {
                        Text(e).dsFont(.footnote).foregroundColor(DS.Color.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DSButton(L10n.t(T.memberAskButton, "Complete my details"), icon: "pencil") {
                        store.editing = true
                        authVM.status = .authenticatedNoProfile
                    }
                }
                .padding(DS.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.warning.opacity(DS.Opacity.tintFillSoft)))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.warning.opacity(DS.Opacity.tintStroke), lineWidth: DS.Border.width))
                // تصعد مرة حين يصل طلب الإدارة — مثل أقسام مربّع التسجيل؛ «تقليل الحركة»: تلاشٍ
                .dsEntrance(delay: DSMotion.sectionsAfterHeader, y: DSMotion.rise, scale: DSMotion.riseScale)
            }
        }
        .task { await store.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { _ in
            Task { await store.refresh() }
        }
    }
}

/// إطار «مطلوب من الإدارة» حول حقل في مربّع التسجيل
struct CompletionAskHighlight: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Label(L10n.t(AdminJoinBoxRules.Ar.memberAskRequired, "Requested by the admins"),
                      systemImage: "exclamationmark.circle.fill")
                    .dsFont(.caption).foregroundColor(DS.Color.warning)
                content
            }
            .padding(DS.Spacing.sm)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(DS.Color.warning, lineWidth: DS.Border.widthBold))
        } else {
            content
        }
    }
}

extension View {
    func completionAskHighlight(_ on: Bool) -> some View { modifier(CompletionAskHighlight(on: on)) }
}
