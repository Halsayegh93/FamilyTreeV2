import SwiftUI
import Supabase
import Combine

// MARK: - «مراجعة بعد الموافقة» (طلب المالك ٢٠٢٦-١١-٢٥، الخيار «أ»: كل طلب يُقبل يدخل المراجعة)
//
// الموافقة نفسها لا تتغيّر. بعد أن يصير الطلب «مقبولاً» يعلّمه السيرفر «بانتظار المراجعة» (20261125130000)، ويراجعه
// المختص: المراقب لطلبات الشجرة والأعضاء، والمشرف للبلاغات، والمالك دائماً، والمالك/المدير مكان المختص حين لا مختص
// نشط. لا أحد يراجع موافقته أو طلبه (إلا المالك). «سليم ✓» أو «فيه ملاحظة» بنص يصل لمن وافق وللمالك والمدير.
// الشكل (مرجع Uizze: Bullpane «Queue monitoring overview»): عنوان «بانتظار المراجعة · N» فوق القائمة، شريحة حالة
// بلون معناها، وسطر واحد بنقاط فاصلة.

/// الطلبات المقبولة التي تنتظر المراجعة — جلب واحد للوارد ولصفحة المراجعة
@MainActor
final class PostReviewStore: ObservableObject {
    static let shared = PostReviewStore()
    @Published private(set) var pending: [AdminRequest] = []
    @Published private(set) var loaded = false
    private let supabase = SupabaseConfig.client

    func refresh() async {
        do {
            let rows: [AdminRequest] = try await supabase.from("admin_requests")
                .select("*, member:members_masked!member_id(*)")
                .eq("status", value: "approved")
                .eq("review_status", value: "pending")
                .order("replied_at", ascending: false)
                .limit(100)
                .execute().value
            pending = rows
        } catch {
            // قبل ترحيل السيرفر لا عمود للمراجعة — لا شيء يُراجَع (كما اليوم)
            Log.warning("[PostReview] تعذّر جلب طلبات المراجعة: \(error.localizedDescription)")
            pending = []
        }
        loaded = true
    }

    /// nil = تمّت، وإلا رسالة تُعرض (رسالة السيرفر العربية حين توجد)
    func review(_ id: UUID, ok: Bool, note: String?) async -> String? {
        nonisolated struct Params: Encodable {
            let p_request_id: String
            let p_result: String
            let p_note: String?
        }
        let text = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        do {
            try await supabase.rpc("review_admin_request",
                                   params: Params(p_request_id: id.uuidString, p_result: ok ? "ok" : "flagged",
                                                  p_note: text.isEmpty ? nil : text))
                .execute()
            pending.removeAll { $0.id == id }
            return nil
        } catch {
            Log.error("[PostReview] تعذّرت المراجعة: \(error.localizedDescription)")
            let pg = error as? PostgrestError
            let server = pg?.message.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if pg?.hint == "already_reviewed" { pending.removeAll { $0.id == id } }
            if L10n.isArabic, server.range(of: "\\p{Arabic}", options: .regularExpression) != nil { return server }
            return L10n.t("تعذّرت المراجعة. حاول مرة أخرى.", "Couldn't save the review. Try again.")
        }
    }

    // MARK: من يراجع ماذا (نفس قواعد السيرفر — السيرفر يحرسها أيضاً)

    /// مختص النوع: المشرف للبلاغات، المراقب لغيرها؛ nil = خارج المراجعة
    static func specialistRole(for type: String) -> FamilyMember.UserRole? {
        switch type {
        case "news_report", "content_report": return .supervisor
        case "contact_message", "lineage_request", "relative_remove": return nil
        default: return .monitor
        }
    }

    /// يقدر المشاهد يراجع هذا الطلب؟ — يُخفى عنه ما لا يقدر عليه (موافقته، طلبه، أو ليس مختصه)
    static func canReview(_ r: AdminRequest, me: FamilyMember?, members: [FamilyMember]) -> Bool {
        guard let me, let role = specialistRole(for: r.requestType) else { return false }
        if me.role == .owner { return true }
        let mine: Set<UUID> = [me.id]
        if let by = r.repliedBy, mine.contains(by) { return false }
        if let by = r.approvedBy, mine.contains(by) { return false }
        if mine.contains(r.requesterId) || mine.contains(r.memberId) { return false }
        if me.role == role { return true }
        if me.role == .admin {
            return !members.contains { $0.role == role && $0.status == .active }
        }
        return false
    }
}

// MARK: - مدخل «الوارد»

/// سطر في أعلى «الوارد» حين توجد طلبات بانتظار مراجعتك — يفتح صفحة المراجعة
struct PostReviewInboxEntry: View {
    @ObservedObject private var store = PostReviewStore.shared
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var open = false

    private var mine: [AdminRequest] {
        store.pending.filter { PostReviewStore.canReview($0, me: authVM.currentUser, members: memberVM.allMembers) }
    }

    var body: some View {
        Group {
            if !mine.isEmpty {
                Button { open = true } label: {
                    HStack(spacing: DS.Spacing.md) {
                        AdminIconSquare(symbol: "checkmark.shield.fill", tint: DS.Color.warning)
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(verbatim: L10n.t("بانتظار المراجعة · \(mine.count)", "Awaiting review · \(mine.count)"))
                                .dsFont(.hubRow)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("طلبات قُبلت وتحتاج مراجعتك", "Approved requests that need your review"))
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        Spacer(minLength: DS.Spacing.xs)
                        Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                            .dsGlyph(DS.Glyph.sm, weight: .semibold)
                            .foregroundColor(DS.Color.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(DSPressStyle())
                .adminCard()
                .accessibilityHint(L10n.t("يفتح صفحة المراجعة", "Opens the review page"))
            }
        }
        // كل ظهور للوارد يحدّث العدد (موافقات جديدة من الآخرين)
        .task { await store.refresh() }
        .dsTallBox(isPresented: $open) {
            PostReviewQueuePage(onClose: { open = false })
        }
    }
}

// MARK: - صفحة المراجعة

struct PostReviewQueuePage: View {
    let onClose: () -> Void
    @ObservedObject private var store = PostReviewStore.shared
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var busyId: UUID?
    @State private var noteFor: AdminRequest?
    @State private var failure: String?

    private var mine: [AdminRequest] {
        store.pending.filter { PostReviewStore.canReview($0, me: authVM.currentUser, members: memberVM.allMembers) }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("بانتظار المراجعة", "Awaiting review"),
            subtitle: L10n.t("طلبات قُبلت — راجع ما تم فيها", "Approved requests — check what was done"),
            icon: "checkmark.shield.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: onClose
        ) {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                if let failure {
                    DSNoteCard(failure, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
                if mine.isEmpty {
                    DSEmptyView(L10n.t("ما في شي ينتظر مراجعتك", "Nothing awaits your review"),
                                message: L10n.t("كل الطلبات المقبولة رُوجعت.", "Every approved request has been reviewed."),
                                style: .card)
                } else {
                    AdminSectionLabel(title: L10n.t("بانتظار المراجعة · \(mine.count)", "Awaiting review · \(mine.count)"))
                    ForEach(mine) { r in
                        PostReviewCard(request: r, busy: busyId == r.id,
                                       onOK: { Task { await run(r, ok: true, note: nil) } },
                                       onFlag: { noteFor = r })
                    }
                }
            }
        }
        .task { await store.refresh() }
        .dsCenterBox(item: $noteFor) { r in
            PostReviewNoteBox(request: r, onSend: { note in
                noteFor = nil
                Task { await run(r, ok: false, note: note) }
            }, onCancel: { noteFor = nil })
        }
    }

    private func run(_ r: AdminRequest, ok: Bool, note: String?) async {
        busyId = r.id
        failure = nil
        if let message = await store.review(r.id, ok: ok, note: note) {
            failure = message
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        busyId = nil
    }
}

/// بطاقة طلب مقبول: النوع والمعنيّ، ما تم، من وافق ومتى، وزرّا «سليم ✓» و«فيه ملاحظة»
private struct PostReviewCard: View {
    let request: AdminRequest
    let busy: Bool
    let onOK: () -> Void
    let onFlag: () -> Void
    @EnvironmentObject private var memberVM: MemberViewModel

    private var subjectName: String {
        let m = request.member ?? memberVM.member(byId: request.memberId)
        return m.map { $0.fullName.isEmpty ? $0.firstName : $0.fullName } ?? ""
    }

    private var metaLine: String {
        var parts: [String] = []
        if let by = request.approvedBy ?? request.repliedBy, let m = memberVM.member(byId: by) {
            parts.append(L10n.t("وافق عليه: \(m.firstName)", "Approved by \(m.firstName)"))
        }
        if let when = DateHelper.displayDateTime(request.approvedAt ?? request.repliedAt) { parts.append(when) }
        return parts.joined(separator: " · ")
    }

    /// «ما تم»: القيمة الجديدة أو التفاصيل — نص قصير للمراجع
    private var whatLine: String? {
        let v = (request.newValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty, v.count < 160, !v.hasPrefix("{") { return v }
        let d = (request.details ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty, d.count < 200, !d.hasPrefix("{") { return d }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(verbatim: AdminTrailText.typeTitle(request))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    if !subjectName.isEmpty {
                        Text(verbatim: subjectName)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: DS.Spacing.xs)
                DSStatusChip(text: L10n.t("بانتظار المراجعة", "Awaiting review"), tint: DS.Color.warning, size: .mini)
            }
            if let whatLine {
                Text(verbatim: whatLine)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.cardBackgroundSoft))
            }
            if !metaLine.isEmpty {
                Text(verbatim: metaLine)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("سليم ✓", "Looks right"), icon: "checkmark", tint: DS.Color.success,
                         isLoading: busy, action: onOK)
                DSButton(L10n.t("فيه ملاحظة", "Has an issue"), icon: "exclamationmark.bubble", role: .cancel, action: onFlag)
                    .disabled(busy)
            }
        }
        .adminCard()
    }
}

/// مربّع «فيه ملاحظة»: الملاحظة مطلوبة وتصل لمن وافق وللمالك والمدير
private struct PostReviewNoteBox: View {
    let request: AdminRequest
    let onSend: (String) -> Void
    let onCancel: () -> Void
    @State private var note = ""

    var body: some View {
        DSComposer(
            title: L10n.t("فيه ملاحظة", "Has an issue"),
            subtitle: AdminTrailText.typeTitle(request),
            icon: "exclamationmark.bubble.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("إرسال", "Send"),
            actionIcon: "paperplane.fill",
            cancelTitle: L10n.t("إلغاء", "Cancel"),
            canSubmit: !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSubmit: { onSend(note) },
            onCancel: onCancel
        ) {
            DSComposerField(icon: "text.bubble", label: L10n.t("الملاحظة", "Note"),
                            placeholder: L10n.t("شنو الغلط في اللي تم؟", "What's wrong with what was done?"),
                            text: $note, multiline: true, lines: 2...5, limit: 1000)
            Text(L10n.t("تصل لمن وافق على الطلب وللمالك والمدير.", "Goes to whoever approved it and to the owner and admins."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
