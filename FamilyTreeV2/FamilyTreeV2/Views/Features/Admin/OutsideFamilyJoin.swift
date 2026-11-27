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

/// قسم في مربّع الربط: «من خارج العائلة» ← «قبول «من خارج العائلة»» (للأنثى — للذكر خيار «ابن بنت» نفسه في مربّعه)
struct OutsideJoinApproveSection: View {
    let member: FamilyMember
    var onApproved: () -> Void

    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var busy = false
    @State private var errorText: String?
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            OutsideJoinTag(member: member)
            Text(L10n.t(SignupOriginRules.Ar.approveOutsideNote,
                        "The account is approved now; on opening the app the person picks the mother and the father's name, then the admins confirm it in the inbox."))
                .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            DSButton(L10n.t(SignupOriginRules.Ar.approveOutside, "Approve «from outside the family»"),
                     icon: "checkmark", tint: DS.Color.success, isLoading: busy) { confirm = true }
                .disabled(busy)
            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil)
        .dsAlert(L10n.t(SignupOriginRules.Ar.approveOutside, "Approve «from outside the family»"), isPresented: $confirm) {
            Button(L10n.t("موافقة", "Approve")) { approve() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(verbatim: member.displayFullName)
        }
    }

    private func approve() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                try await DaughterSons.approveJoin(memberId: member.id)
                await DaughterSonsIndex.shared.refresh(force: true)
                await OutsideJoinStore.shared.refresh(force: true)
                await memberVM.fetchAllMembers(force: true)
                busy = false
                DSMomentToast.show(L10n.t("تمت الموافقة", "Approved"))
                onApproved()
            } catch {
                errorText = DaughterSons.message(error)
                busy = false
            }
        }
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

struct OutsideLineageRequestCard: View {
    let request: AdminRequest
    @ObservedObject var adminRequestVM: AdminRequestViewModel

    @State private var suggestions: [LineageMotherSuggestion] = []
    @State private var loaded = false
    @State private var picked: UUID?
    @State private var busy = false
    @State private var showReject = false
    @State private var reason = ""

    private typealias T = SignupOriginRules.Ar

    var body: some View {
        let d = OutsideLineageDetails.parse(request.details)
        let pickedRow = suggestions.first { $0.id == picked }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "arrow.triangle.branch", tint: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t(T.inboxTypedTitle, "Lineage request · complete registration"))
                        .dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(request.member?.fullName ?? L10n.t("العضو", "the member"))
                        .dsFont(.footnote).foregroundColor(DS.Color.textSecondary).dsNameLines()
                }
                Spacer(minLength: 0)
                if let created = request.createdAt {
                    Text(DateHelper.relativeTime(from: created)).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                }
            }
            VStack(spacing: 0) {
                row(L10n.t("الوالدة", "Mother"), SignupOriginRules.tidy((d?.motherTypedName ?? "") + " " + (d?.motherFamily ?? "")))
                Divider()
                row(L10n.t("الوالد", "Father"), d?.fatherName ?? "—", note: L10n.t(T.fatherDerivedNote, "From the registered name."))
            }
            .padding(.horizontal, DS.Spacing.sm)
            .dsCard(padding: nil)
            Group {
                DSBoxSectionTitle(title: L10n.t(T.inboxPickMother, "Pick the mother from the family's daughters"),
                                  icon: "person.fill", tint: DS.Color.female)
                if !loaded {
                    DSPageLoader(L10n.t("جارٍ البحث", "Searching"), fillsSpace: false)
                } else if suggestions.isEmpty {
                    Text(L10n.t(T.inboxNoSuggestions, "No daughters match this name. Contact the requester or reject."))
                        .dsFont(.footnote).foregroundColor(DS.Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(spacing: 0) {
                        ForEach(suggestions) { m in
                            suggestionRow(m)
                            if m.id != suggestions.last?.id { Divider() }
                        }
                    }
                    .dsCard(padding: DS.Spacing.sm)
                }
                if let pickedRow, pickedRow.husbandId != nil, !pickedRow.husbandMatches {
                    DSNoteCard(pickedRow.husbandInFamily
                               ? L10n.t("زوجها من العائلة — يُربط صاحب الطلب تحت والده في الشجرة، لا هنا.",
                                        "Her husband is from the family — link the requester under his father in the tree instead.")
                               : L10n.t("لها زوج مسجّل باسم آخر «\(pickedRow.husbandName ?? "")» — صحّح الشجرة أولاً أو ارفض الطلب.",
                                        "She has a different recorded husband «\(pickedRow.husbandName ?? "")» — fix the tree first or reject."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.warning)
                }
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("موافقة", "Approve"),
                         icon: "checkmark", tint: DS.Color.success, isLoading: busy) { decide(approve: true) }
                    .disabled(busy || picked == nil)
                DSButton(L10n.t("رفض", "Reject"), icon: "xmark", role: .cancel) { reason = ""; showReject = true }
            }
            .disabled(busy)
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
        .task(id: request.id) { await load() }
        .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $showReject) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $reason)
                .dsAlertField()
            Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) { decide(approve: false) }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("يصله السبب ويُرسل بيانات الوالدة من جديد.", "They get the reason and send the mother's details again."))
        }
    }

    private func row(_ label: String, _ value: String, note: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(label).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                .frame(minWidth: DS.Icon.rowLarge + DS.Spacing.lg, alignment: .leading)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: value.isEmpty ? "—" : value).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note { Text(note).dsFont(.caption).foregroundColor(DS.Color.textTertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: DS.Icon.tapTarget)
    }

    private func suggestionRow(_ m: LineageMotherSuggestion) -> some View {
        let selected = picked == m.id
        return Button { picked = selected ? nil : m.id } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(name: m.fullName, avatarUrl: nil, size: DS.Icon.row, roleColor: DS.Color.female)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: m.fullName).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    // ما يطابق الاسم المكتوب والوالد المشتق ← شريحة خضراء
                    NamePartChips(parts: MotherPickRules.markMatches(
                        MotherPickRules.disambiguationParts(fatherName: m.fatherName, husbandName: m.husbandName),
                        typedName: OutsideLineageDetails.parse(request.details)?.motherTypedName,
                        expectedHusband: OutsideLineageDetails.parse(request.details)?.fatherName))
                    if m.husbandMatches {
                        Text(L10n.t(T.inboxHusbandMatches, "Her husband matches the father's name"))
                            .dsFont(.badge).foregroundColor(DS.Color.success)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.lg)
                    .foregroundColor(selected ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: DS.Icon.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func load() async {
        do {
            suggestions = try await SupabaseConfig.client
                .rpc("lineage_mother_suggestions", params: ["p_request_id": request.id.uuidString]).execute().value
            // بنت واحدة زوجها يطابق الوالد ← مختارة مسبقاً (المراجع يؤكّد)
            let matching = suggestions.filter(\.husbandMatches)
            if picked == nil, matching.count == 1 { picked = matching[0].id }
        } catch {
            if !ErrorHelper.isCancellation(error) {
                Log.warning("[OutsideLineage] lineage_mother_suggestions: \(error.localizedDescription)")
            }
        }
        loaded = true
    }

    private func decide(approve: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            let ok = await adminRequestVM.decideLineage(request, approve: approve,
                                                        reason: approve ? nil : reason,
                                                        motherId: approve ? picked : nil)
            busy = false
            if ok, approve { DSMomentToast.show(L10n.t("تم الاعتماد", "Approved")) }
        }
    }
}

/// القيم وحدها بنقاط هادئة: الوالد · الجد · سنة الميلاد (· الزوج) — بلا التسميات الرمادية (المالك «شيل الكلمات الصغيرة»)؛
/// المطابق لبيانات الطلب أخضر، والقارئ الصوتي يقرأ التسمية مع القيمة («الوالد حسن»)
struct NamePartChips: View {
    let parts: [MotherPickRules.NamePart]

    var body: some View {
        DSChipFlow(spacing: DS.Spacing.xxs) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                HStack(spacing: DS.Spacing.xxs) {
                    if i > 0 {
                        Text(verbatim: "·").foregroundColor(DS.Color.textTertiary).accessibilityHidden(true)
                    }
                    Text(verbatim: p.value + (p.matches ? " ✓" : ""))
                        .foregroundColor(p.matches ? DS.Color.success : DS.Color.textSecondary)
                        .padding(.horizontal, p.matches ? DS.Spacing.xsm : 0)
                        .background(Capsule().fill(p.matches ? DS.Color.success.opacity(DS.Opacity.tintFill) : .clear))
                }
                .dsFont(.caption)
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(p.label + " " + p.value + (p.matches ? L10n.t("، مطابق", ", matches") : ""))
            }
        }
    }
}
