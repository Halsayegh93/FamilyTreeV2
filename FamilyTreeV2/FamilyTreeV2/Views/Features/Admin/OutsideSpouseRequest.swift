import SwiftUI
import Supabase

// MARK: - «الوارد»: طلب ربط الزوج أو الزوجة من العائلة (العيّنة spouse2.html القسم ٣، المالك ٢٠٢٦-١١-٢٨)
//
// البطاقة نفسها تحمل كل شيء (كما في العيّنة): نوع الطلب ووقته · الاسم · الاسم المكتوب · مقترحات من الشجرة بزرّ «ربط»
// (`link_outside_spouse`)؛ وإن لم يوجد ما يُربط: «الزوجة غير مضافة بالتطبيق» + (الوالد موجود) «إضافة «فلانة» تحت والدها وربط
// الزوج» (`add_daughter_and_link_spouse`) · «اختيار من الشجرة يدوياً» (`DSMemberPickerBox`: بنات العائلة للزوجة، رجال العائلة
// للزوج) · «طلب معلومات من العضو» (`ask_join_completion` بحقل `spouse_name`) · «رفض مع سبب» (`reject_spouse_request`).
// الأزرار وترتيبها: `SpouseLinkRules.actions`.

enum SpouseLinkAdmin {
    static func suggestions(_ requestId: UUID) async throws -> SpouseLinkRules.Suggestions {
        try await SupabaseConfig.client.rpc("spouse_link_suggestions", params: ["p_request_id": requestId.uuidString])
            .execute().value
    }

    static func link(_ requestId: UUID, target: UUID, wifeNode: UUID?) async throws {
        var p: [String: AnyJSON] = ["p_request_id": .string(requestId.uuidString), "p_target_id": .string(target.uuidString)]
        p["p_wife_node_id"] = wifeNode.map { .string($0.uuidString) } ?? .null
        _ = try await SupabaseConfig.client.rpc("link_outside_spouse", params: p).execute()
    }

    static func addUnderFather(_ requestId: UUID, fatherId: UUID, firstName: String) async throws {
        let p: [String: AnyJSON] = ["p_request_id": .string(requestId.uuidString), "p_father_id": .string(fatherId.uuidString),
                                   "p_first_name": .string(firstName)]
        _ = try await SupabaseConfig.client.rpc("add_daughter_and_link_spouse", params: p).execute()
    }

    static func askInfo(_ requestId: UUID, note: String) async throws {
        let n = SignupOriginRules.tidy(note)
        let p: [String: AnyJSON] = ["p_request_id": .string(requestId.uuidString), "p_fields": .array([.string("spouse_name")]),
                                   "p_note": n.isEmpty ? .null : .string(n)]
        _ = try await SupabaseConfig.client.rpc("ask_join_completion", params: p).execute()
    }

    static func reject(_ requestId: UUID, reason: String) async throws {
        let r = SignupOriginRules.tidy(reason)
        let p: [String: AnyJSON] = ["p_request_id": .string(requestId.uuidString), "p_reason": r.isEmpty ? .null : .string(r)]
        _ = try await SupabaseConfig.client.rpc("reject_spouse_request", params: p).execute()
    }

    static func message(_ error: Error) -> String {
        switch (error as? PostgrestError)?.hint ?? "" {
        case "bad_target": return L10n.t("الاختيار ليس في الشجرة بالصفة المطلوبة.", "That person isn't in the tree as required.")
        case "spouse_in_family": return L10n.t("زوجها من العائلة — لا يُكتب فوقه.", "Her husband is from the family — not overwritten.")
        case "spouse_has_account": return L10n.t("مربوط بحساب آخر في التطبيق.", "Linked to another account in the app.")
        case "own_request": return L10n.t("لا تقرّر في طلبك.", "You can't decide your own request.")
        default: return DaughterSons.message(error)
        }
    }
}

/// البطاقة في قائمة «الوارد»
struct OutsideSpouseRequestCard: View {
    let request: AdminRequest
    @ObservedObject var adminRequestVM: AdminRequestViewModel

    var body: some View {
        OutsideSpouseRequestContent(requestId: request.id,
                                    memberName: request.member?.fullName ?? L10n.t("العضو", "the member"),
                                    age: request.createdAt.map { DateHelper.relativeTime(from: $0) },
                                    details: SpouseLinkRules.Details.parse(request.details),
                                    canDecide: adminRequestVM.canHandleRelativeAdd,
                                    men: adminRequestVM.memberVM?.allMembers ?? []) {
            adminRequestVM.lineageRequests.removeAll { $0.id == request.id }
            Task {
                _ = try? await WomenStore.fetch()
                NotificationCenter.default.post(name: .womenMembersChanged, object: nil)
            }
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil, radius: DS.Hub.tileRadius)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: DS.Spacing.xsm, leading: DS.Spacing.lg, bottom: DS.Spacing.xsm, trailing: DS.Spacing.lg))
    }
}

struct OutsideSpouseRequestContent: View {
    let requestId: UUID
    let memberName: String
    let age: String?
    let details: SpouseLinkRules.Details?
    let canDecide: Bool
    /// رجال الشجرة (للمنتقي اليدوي عند «الزوج»)
    let men: [FamilyMember]
    let onDone: () -> Void
    /// المعاينة تحقن الاقتراحات (بلا سيرفر)
    var injected: SpouseLinkRules.Suggestions? = nil

    private typealias S = SpouseLinkRules
    private typealias T = SpouseLinkRules.Ar

    @State private var sugg: S.Suggestions?
    @State private var busy = false
    @State private var errorText: String?
    @State private var confirm: S.Action?
    @State private var showPicker = false
    @State private var pickerSearch = ""
    @State private var showAsk = false
    @State private var askNote = ""
    @State private var showReject = false
    @State private var reason = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var relation: S.Relation { details?.relation ?? .wife }
    private var matches: [S.Match] { sugg?.matches ?? [] }
    private var fathers: [S.Father] { sugg?.fathers ?? [] }
    private var actions: [S.Action] { S.actions(relation, matches: matches, fathers: fathers) }
    private var typedFirst: String { S.firstName(details?.typedName ?? "") }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            header
            if sugg == nil {
                DSPageLoader(fillsSpace: false).padding(.vertical, DS.Spacing.xs)
            } else {
                content.transition(.dsReveal(reduceMotion: reduceMotion))
            }
            if let errorText {
                Text(errorText).dsFont(.footnote).foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .animation(reduceMotion ? DSMotion.fade : DSMotion.reveal, value: sugg == nil)
        .task(id: requestId) { await load() }
        .dsAlert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button(L10n.t("تأكيد الربط", "Confirm link")) { if let c = confirm { run(c) } }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { confirm = nil }
        } message: {
            Text(confirmBody)
        }
        .dsAlert(T.askTitle, isPresented: $showAsk) {
            TextField(T.askNotePlaceholder, text: $askNote).dsAlertField()
            Button(T.askSend) { ask() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(T.askBody)
        }
        .dsAlert(L10n.t("سبب الرفض", "Rejection Reason"), isPresented: $showReject) {
            TextField(L10n.t("اكتب السبب (اختياري)", "Reason (optional)"), text: $reason).dsAlertField()
            Button(L10n.t("إرسال الرفض", "Send Rejection"), role: .destructive) { reject() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
        .dsCenterBox(isPresented: $showPicker) { picker }
    }

    // MARK: الرأس: النوع والوقت · الاسم · الاسم المكتوب

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack(spacing: DS.Spacing.sm) {
                SignupRingsGlyph(size: DS.Glyph.lg)
                    .foregroundColor(DS.Color.sadu)
                Text(S.inboxTitle(relation)).dsFont(.caption).foregroundColor(DS.Color.textSecondary)
                Spacer(minLength: 0)
                if let age { Text(age).dsFont(.caption).foregroundColor(DS.Color.textTertiary) }
            }
            Text(verbatim: memberName).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary).dsNameLines()
            if let d = details {
                Text(verbatim: T.typedLine(relation) + d.spouseName)
                    .dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: المحتوى حسب الاقتراحات

    @ViewBuilder private var content: some View {
        let linkable = matches.filter(\.canLink)
        if !linkable.isEmpty {
            Text(T.suggestions).dsFont(.sectionTitle).foregroundColor(DS.Color.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(linkable.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { DSDivider() }
                    matchRow(m)
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
        }
        if S.notInApp(relation, matches: matches) {
            noteBox(title: T.notInApp(relation), body: T.notInAppBody(relation), tint: DS.Color.warning)
        }
        if let f = fathers.first, actions.contains(.addUnderFather(f.id)) {
            fatherBox(f)
        }
        if canDecide {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(actions.filter { if case .link = $0 { return false }; return true }, id: \.self) { a in
                    actionButton(a)
                }
            }
            Button { reason = ""; showReject = true } label: {
                Text(T.rejectWithReason).dsFont(.chip).foregroundColor(DS.Color.error)
                    .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private func matchRow(_ m: S.Match) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: m.fullName).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if let h = m.husbandName, !h.isEmpty {
                    Text(verbatim: T.linkedTo(relation) + h).dsFont(.caption).foregroundColor(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: DS.Spacing.sm)
            if canDecide {
                DSChipButton(T.link, icon: "link", tint: DS.Color.success, size: .small, isLoading: busy) {
                    confirm = .link(m.id)
                }
                .disabled(busy)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func noteBox(title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title).dsFont(.rowTitle).foregroundColor(tint)
            Text(body).dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .fill(tint.opacity(DS.Opacity.tintFillSoft)))
    }

    private func fatherBox(_ f: S.Father) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Label {
                Text(T.fatherFound).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
            } icon: {
                Image(systemName: "checkmark.circle.fill").dsGlyph(DS.Glyph.md).foregroundColor(DS.Color.success)
            }
            Text(verbatim: f.fullName).dsFont(.footnote).foregroundColor(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.cardBorderStrong, lineWidth: DS.Border.width))
    }

    @ViewBuilder private func actionButton(_ a: S.Action) -> some View {
        switch a {
        case .addUnderFather:
            DSButton(T.addUnderFather(typedFirst), icon: "person.badge.plus", tint: DS.Color.success, isLoading: busy) {
                confirm = a
            }
            .disabled(busy)
        case .pickManually:
            DSButton(T.pickManually, icon: "list.bullet", role: .cancel) { pickerSearch = ""; showPicker = true }
                .disabled(busy)
        case .askInfo:
            DSButton(T.askInfo, icon: "questionmark.bubble", role: .cancel) { askNote = ""; showAsk = true }
                .disabled(busy)
        case .link:
            EmptyView()
        }
    }

    // MARK: المنتقي اليدوي

    private var pickerCandidates: [FamilyMember] {
        if relation == .wife {
            let menIds = Set(men.map(\.id))
            return WomenStore.cache.filter { $0.isFemale && $0.fatherId.map(menIds.contains) == true }
        }
        return men.filter { !$0.isFemale && $0.role != .pending }
    }

    private var picker: some View {
        DSMemberPickerBox(title: T.pickManually,
                          subtitle: relation == .wife ? L10n.t("بنات العائلة في شجرة النساء", "Family daughters in the women's tree")
                                                      : L10n.t("رجال العائلة في الشجرة", "Family men in the tree"),
                          icon: relation == .wife ? "person.fill" : "person.fill",
                          candidates: pickerCandidates, search: $pickerSearch,
                          requiresSpecificQuery: false, listsAllWhenEmpty: false,
                          tint: relation == .wife ? DS.Color.female : DS.Color.male,
                          onPick: { m in
                              showPicker = false
                              confirm = .link(m.id)
                          },
                          onCancel: { showPicker = false })
    }

    // MARK: التأكيد والتنفيذ

    private var confirmTitle: String {
        if case .addUnderFather = confirm { return T.addUnderFather(typedFirst) }
        return L10n.t("ربط الحساب بالشجرة", "Link the account to the tree")
    }

    private var confirmBody: String {
        let who = targetName(confirm)
        switch confirm {
        case .addUnderFather?:
            return L10n.t("تُضاف «\(typedFirst)» بنتاً لـ«\(who)» في شجرة النساء، ويُربط «\(memberName)» زوجاً لها. لا يمكن التراجع من التطبيق.",
                          "«\(typedFirst)» is added under «\(who)», and «\(memberName)» is linked as her husband.")
        default:
            return relation == .wife
                ? L10n.t("يُربط «\(memberName)» زوجاً لـ«\(who)» في شجرة النساء، ويكتمل تسجيله. لا يمكن التراجع من التطبيق.",
                         "«\(memberName)» is linked as «\(who)»'s husband.")
                : L10n.t("تُربط «\(memberName)» زوجةً لـ«\(who)» في شجرة النساء، ويكتمل تسجيلها. لا يمكن التراجع من التطبيق.",
                         "«\(memberName)» is linked as «\(who)»'s wife.")
        }
    }

    private func targetName(_ a: S.Action?) -> String {
        switch a {
        case .link(let id)?:
            return matches.first { $0.id == id }?.fullName
                ?? pickerCandidates.first { $0.id == id }?.fullName ?? ""
        case .addUnderFather(let id)?:
            return fathers.first { $0.id == id }?.fullName ?? ""
        default:
            return ""
        }
    }

    private func load() async {
        if let injected { sugg = injected; return }
        do {
            sugg = try await SpouseLinkAdmin.suggestions(requestId)
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            sugg = S.Suggestions()
            errorText = SpouseLinkAdmin.message(error)
        }
    }

    private func run(_ a: S.Action) {
        confirm = nil
        guard canDecide, !busy, injected == nil, NetworkMonitor.shared.requireOnline() else { return }
        busy = true
        errorText = nil
        Task {
            do {
                switch a {
                case .link(let id):
                    try await SpouseLinkAdmin.link(requestId, target: id, wifeNode: matches.first { $0.id == id }?.wifeNodeId)
                case .addUnderFather(let f):
                    try await SpouseLinkAdmin.addUnderFather(requestId, fatherId: f, firstName: typedFirst)
                default:
                    busy = false
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                DSMomentToast.show(T.linked)
                onDone()
            } catch {
                errorText = SpouseLinkAdmin.message(error)
            }
            busy = false
        }
    }

    private func ask() {
        guard canDecide, !busy, injected == nil else { return }
        busy = true
        errorText = nil
        let note = askNote
        Task {
            do {
                try await SpouseLinkAdmin.askInfo(requestId, note: note)
                DSMomentToast.show(L10n.t(AdminJoinBoxRules.Ar.askSent, "Request for missing details sent"))
            } catch {
                errorText = CompletionAsk.message(error)
            }
            busy = false
        }
    }

    private func reject() {
        guard canDecide, !busy, injected == nil else { return }
        busy = true
        errorText = nil
        let r = reason
        Task {
            do {
                try await SpouseLinkAdmin.reject(requestId, reason: r)
                DSMomentToast.show(L10n.t("تم الرفض", "Rejected"))
                onDone()
            } catch {
                errorText = SpouseLinkAdmin.message(error)
            }
            busy = false
        }
    }
}

#if DEBUG
/// معاينة التصوير (`-uiPreviewSignup admin-spouse[-found]`): الحالتان — الزوجة غير مضافة والوالد موجود، أو مقترحة بزرّ «ربط»
struct OutsideSpouseRequestPreview: View {
    let found: Bool

    var body: some View {
        let details = SpouseLinkRules.Details.parse(
            #"{"kind":"outside_spouse","relation":"wife","spouse_typed_name":"فاطمة أحمد زيد حسن","spouse_name":"فاطمة أحمد زيد حسن المحمدعلي"}"#)
        var s = SpouseLinkRules.Suggestions()
        if found {
            s.matches = [SpouseLinkRules.Match(id: UUID(), fullName: "فاطمة أحمد زيد حسن علي حسين حسن محمدعلي حسن المحمدعلي",
                                               fatherId: UUID(), canLink: true, wifeNodeId: nil)]
        }
        s.fathers = [SpouseLinkRules.Father(id: UUID(), fullName: "أحمد زيد حسن علي حسين حسن محمدعلي حسن المحمدعلي")]
        return ScrollView {
            OutsideSpouseRequestContent(requestId: UUID(), memberName: "محمد حسن حسين الكندري", age: L10n.t("قبل ساعة", "1h ago"),
                                        details: details, canDecide: true, men: [], onDone: {}, injected: s)
                .padding(DS.Spacing.md)
                .dsCard(padding: nil, radius: DS.Hub.tileRadius)
                .padding(DS.Spacing.lg)
        }
        .background(DS.Hub.background.ignoresSafeArea())
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}
#endif
