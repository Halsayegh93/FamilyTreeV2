import SwiftUI
import Combine
import Supabase

// MARK: - «من خارج العائلة» في «الوارد» (موافقة المالك ٢٠٢٦-١١-٢٧، الوحدة R1)
//
// طلب الانضمام من شاشة «البيانات الشخصية» (من خارج العائلة) يحمل `SignupOriginRules.outsideMarker` في تفاصيله.
// «الوارد» يعلّمه «من خارج العائلة» مع الحقول الأربعة (الاسم الرباعي · العائلة · تاريخ الميلاد · الجنس)، والقبول
// = «قبول «من خارج العائلة»» (`approve_join_as_daughter_son` — للأنثى أيضاً بعد ترحيل 20261127160000):
// الحساب يُفعَّل مقيّداً، وعند فتح التطبيق يُستكمل التسجيل باختيار الوالدة واسم الوالد (`LineagePage`).

@MainActor
final class OutsideJoinStore: ObservableObject {
    static let shared = OutsideJoinStore()
    @Published private(set) var ids: Set<UUID> = []
    private var lastFetch: Date?

    private nonisolated struct Row: Decodable { let member_id: UUID }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// طلبات الانضمام/الربط المعلّقة بعلامة «من خارج العائلة» — مرة كل ٣٠ ثانية على الأكثر
    func refresh(force: Bool = false) async {
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < 30 { return }
        lastFetch = Date()
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("admin_requests")
                .select("member_id")
                .in("request_type", values: [RequestType.linkRequest.rawValue, RequestType.joinRequest.rawValue])
                .eq("status", value: ApprovalStatus.pending.rawValue)
                .like("details", pattern: "%\(SignupOriginRules.outsideMarker)%")
                .execute()
                .value
            let next = Set(rows.map(\.member_id))
            if next != ids { ids = next }
        } catch {
            lastFetch = nil
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[OutsideJoin] admin_requests: \(error.localizedDescription)")
            }
        }
    }
}

/// شارة «من خارج العائلة · العائلة: فلان» على طلب الانضمام
struct OutsideJoinTag: View {
    let member: FamilyMember

    var body: some View {
        let family = (member.familyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        DSStatusChip(text: L10n.t(SignupOriginRules.Ar.inboxTag, "From outside the family")
                        + (family.isEmpty ? "" : " · " + family),
                     icon: "link", tint: DS.Color.palm, size: .mini)
    }
}

// MARK: - «استكمال التسجيل» في «الوارد»: اسم الوالدة مكتوباً ← المراجع يختارها ← اعتماد

/// بنت مقترحة من `lineage_mother_suggestions` («بنت فلان · زوجة فلان»، وهل زوجها يطابق الوالد المشتق)
nonisolated struct LineageMotherSuggestion: Decodable, Identifiable, Sendable, Equatable {
    let id: UUID
    let fullName: String
    let fatherName: String?
    let husbandId: UUID?
    let husbandName: String?
    let husbandInFamily: Bool
    let husbandMatches: Bool

    enum CodingKeys: String, CodingKey {
        case id, fullName = "full_name", fatherName = "father_name", husbandId = "husband_id",
             husbandName = "husband_name", husbandInFamily = "husband_in_family", husbandMatches = "husband_matches"
    }
}

/// حمولة طلب «استكمال التسجيل»
nonisolated struct OutsideLineageDetails: Decodable, Sendable {
    let motherTypedName: String?
    let motherFamily: String?
    let fatherName: String?
    enum CodingKeys: String, CodingKey {
        case motherTypedName = "mother_typed_name", motherFamily = "mother_family", fatherName = "father_name"
    }
    static func parse(_ details: String?) -> OutsideLineageDetails? {
        guard let data = details?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OutsideLineageDetails.self, from: data)
    }
}

/// بطاقة طلب «استكمال التسجيل» في «الوارد» — الضغط يفتح مربّعه الصغير (R2): البيانات واقتراحات الوالدة ← «ربط بالوالدة»
/// ← «تأكيد الربط» (`decide_lineage_request(…, p_mother_id)` عبر `decideLineage`)، و«رفض مع سبب»
struct OutsideLineageRequestCard: View {
    let request: AdminRequest
    @ObservedObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject private var memberVM: MemberViewModel

    @State private var open = false

    private typealias T = SignupOriginRules.Ar

    var body: some View {
        let d = OutsideLineageDetails.parse(request.details)
        let mother = SignupOriginRules.tidy((d?.motherTypedName ?? "") + " " + (d?.motherFamily ?? ""))
        return Button { open = true } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "arrow.triangle.branch", tint: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t(T.inboxTypedTitle, "Lineage request · complete registration"))
                        .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.member?.fullName ?? L10n.t("العضو", "the member"))
                        .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).dsNameLines()
                    if !mother.isEmpty {
                        Text(L10n.t("الوالدة: ", "Mother: ") + mother)
                            .dsFont(.caption).foregroundColor(DS.Color.textTertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let created = request.createdAt {
                    Text(DateHelper.relativeTime(from: created)).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                }
                DSChevron()
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityHint(L10n.t("يفتح الطلب", "Opens the request"))
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
        .dsCenterBox(isPresented: $open) {
            AdminJoinBox(subject: .completion(request),
                         requestAge: request.createdAt.map { DateHelper.relativeTime(from: $0) },
                         canDecide: adminRequestVM.canHandleRelativeAdd,
                         onReject: adminRequestVM.canHandleRelativeAdd ? { reason in
                             open = false
                             Task {
                                 if await adminRequestVM.decideLineage(request, approve: false, reason: reason) {
                                     DSMomentToast.show(L10n.t("تم الرفض", "Rejected"))
                                 }
                             }
                         } : nil,
                         onDone: { open = false },
                         onClose: { open = false })
                .environmentObject(adminRequestVM)
                .environmentObject(memberVM)
        }
    }
}

/// القيم وحدها شرائح (R2): الوالد · الجد · سنة الميلاد (· الزوج) — بلا التسميات الرمادية (المالك «شيل الكلمات الصغيرة»)؛
/// المطابق لبيانات الطلب أخضر بعلامة ✓، والقارئ الصوتي يقرأ التسمية مع القيمة («الوالد حسن») — نفس `AdminValueChips`
struct NamePartChips: View {
    let parts: [MotherPickRules.NamePart]

    var body: some View {
        AdminValueChips(chips: parts.map { p in
            AdminJoinBoxRules.Chip(kind: Self.kind(p.label), value: p.value, matches: p.matches)
        })
    }

    private static func kind(_ label: String) -> AdminJoinBoxRules.ChipKind {
        switch label {
        case AdminJoinBoxRules.label(.grandfather): return .grandfather
        case AdminJoinBoxRules.label(.birth): return .birth
        case AdminJoinBoxRules.label(.husband): return .husband
        default: return .father
        }
    }
}
