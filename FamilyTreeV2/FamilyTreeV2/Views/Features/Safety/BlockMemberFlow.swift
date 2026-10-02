import SwiftUI
import UIKit

// MARK: - حظر عضو (Guideline 1.2 — «حظر المستخدمين المسيئين»)
//
// `.dsBlockMemberFlow(target:)` — نفس رسائل «إبلاغ» الموحّدة (dsAlert): تأكيد الحظر ثم
// الحظر على الجهاز (BlockedMembersStore) + بلاغ تلقائي للإدارة + رسالة «تم الحظر».
// إن كان العضو محظوراً مسبقاً تعرض «إلغاء الحظر» بدلها.
// `BlockedMembersSection` — قسم «الأعضاء المحظورون» في «الإشعارات والخصوصية» لإلغاء الحظر.

/// العضو المراد حظره — معرّفه (ملف أو دخول) واسمه كما ظهر في المحتوى
struct BlockTarget: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// أشكال أخرى للاسم (مثل الاسم مع العائلة) — للمطابقة
    var otherNames: [String] = []
}

extension View {
    /// تأكيد «حظر العضو» / «إلغاء الحظر» للعضو في `target` — يُفرَّغ `target` بعد الإجراء
    func dsBlockMemberFlow(target: Binding<BlockTarget?>) -> some View {
        modifier(BlockMemberFlowModifier(target: target))
    }
}

private struct BlockMemberFlowModifier: ViewModifier {
    @Binding var target: BlockTarget?
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @ObservedObject private var store = BlockedMembersStore.shared
    /// اسم من حُظر للتو — يعرض «تم الحظر»
    @State private var blockedName: String?

    private var targetIsBlocked: Bool {
        guard let target else { return false }
        return store.isBlocked(id: target.id, name: target.name)
    }

    func body(content: Content) -> some View {
        content
            .dsAlert(L10n.t("حظر العضو", "Block Member"),
                     isPresented: Binding(get: { target != nil && !targetIsBlocked },
                                          set: { if !$0 { target = nil } }),
                     presenting: target) { t in
                Button(L10n.t("حظر", "Block"), role: .destructive) { block(t) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { target = nil }
            } message: { t in
                Text(L10n.t(
                    "لن تظهر لك أخبار «\(t.name)» ولا تعليقاته، وسيصل بلاغ للإدارة لمراجعة حسابه. لا يُبلَّغ العضو بأنك حظرته، وتقدر تلغي الحظر من الإعدادات ← الإشعارات والخصوصية.",
                    "You won't see posts or comments from “\(t.name)”, and the admins will get a report to review their account. They won't be notified. You can unblock them from Settings → Notifications & Privacy."
                ))
            }
            .dsAlert(L10n.t("إلغاء الحظر", "Unblock Member"),
                     isPresented: Binding(get: { target != nil && targetIsBlocked },
                                          set: { if !$0 { target = nil } }),
                     presenting: target) { t in
                Button(L10n.t("إلغاء الحظر", "Unblock")) { unblock(t) }
                Button(L10n.t("رجوع", "Back"), role: .cancel) { target = nil }
            } message: { t in
                Text(L10n.t("ستظهر لك أخبار «\(t.name)» وتعليقاته مرة أخرى.",
                            "Posts and comments from “\(t.name)” will be visible to you again."))
            }
            .dsAlert(L10n.t("تم الحظر", "Blocked"),
                     isPresented: Binding(get: { blockedName != nil },
                                          set: { if !$0 { blockedName = nil } })) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t(
                    "لن يظهر لك محتوى «\(blockedName ?? "")» بعد الآن، ووصل بلاغ للإدارة لمراجعته خلال ٢٤ ساعة.",
                    "You won't see content from “\(blockedName ?? "")” anymore, and the admins will review the report within 24 hours."
                ))
            }
    }

    private func block(_ t: BlockTarget) {
        // يُفرَّغ أولاً — وإلا تتحوّل الرسالة المفتوحة إلى «إلغاء الحظر» بعد الحظر مباشرة
        target = nil

        var ids = [t.id]
        var names = [t.name] + t.otherNames
        // اربط الاسم بملف العضو في الشجرة (إن وُجد) — التعليق يُحفظ بمعرّف الدخول
        // والخبر بمعرّف الملف، فنحفظ الاثنين ليختفي كل محتواه
        if let member = memberVM.member(byId: t.id) {
            names += [member.fullName, member.displayFullName]
        } else {
            let key = BlockedMembersStore.normalize(t.name)
            let matches = memberVM.allMembers.filter {
                BlockedMembersStore.normalize($0.fullName) == key
                    || BlockedMembersStore.normalize($0.displayFullName) == key
            }
            if matches.count == 1, let member = matches.first {
                ids.append(member.id)
                names += [member.fullName, member.displayFullName]
            }
        }

        let me = authVM.currentUser
        let didBlock = store.block(
            ids: ids,
            names: names,
            selfIds: [me?.id, AccountIdentity.authUserId].compactMap { $0 },
            selfNames: [me?.fullName, me?.displayFullName].compactMap { $0 }
        )
        guard didBlock else { return }   // لا يحظر المستخدم نفسه أبداً

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let name = t.name
        let contentId = t.id
        // بلاغ تلقائي للإدارة — الحظر يعني غالباً إساءة تحتاج مراجعة
        Task {
            _ = await notificationVM.reportContent(
                contentKind: L10n.t("عضو محظور", "blocked member"),
                contentLabel: name,
                contentId: contentId,
                reason: L10n.t("حظره أحد الأعضاء بسبب الإساءة — يرجى مراجعة محتواه وحسابه",
                               "Blocked by a member for abuse — please review their content and account")
            )
        }
        // بعد إغلاق رسالة التأكيد
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { blockedName = name }
    }

    private func unblock(_ t: BlockTarget) {
        target = nil
        if let entry = store.entry(id: t.id, name: t.name) {
            store.unblock(entry)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }
}

// MARK: - قسم «الأعضاء المحظورون» في الإعدادات

struct BlockedMembersSection: View {
    var index: Int = 0
    @ObservedObject private var store = BlockedMembersStore.shared
    @State private var entryToUnblock: BlockedMembersStore.Entry?

    var body: some View {
        DSComposerSection(title: L10n.t("الأعضاء المحظورون", "Blocked Members"),
                          icon: "hand.raised.fill",
                          tint: DS.Color.error,
                          trailing: store.entries.isEmpty ? nil : "\(store.entries.count)",
                          index: index) {
            VStack(spacing: DS.Spacing.sm) {
                if store.entries.isEmpty {
                    HStack(spacing: DS.Spacing.sm) {
                        DSFieldIcon(name: "hand.raised.slash.fill", tint: DS.Color.textTertiary)
                            .accessibilityHidden(true)   // زخرفة
                        Text(L10n.t("لا يوجد أعضاء محظورون", "No blocked members"))
                            .font(DS.Font.plex(13.5, weight: .semibold))
                            .foregroundColor(DS.Color.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .dsRowBox()
                } else {
                    ForEach(store.entries) { entry in
                        row(entry)
                    }
                }
                Text(L10n.t("المحظور لا تظهر لك أخباره ولا تعليقاته، ولا يُبلَّغ بأنك حظرته. تحظر العضو من ملفه أو من قائمة «…» على خبره أو تعليقه.",
                            "You won't see posts or comments from blocked members, and they aren't notified. Block someone from their profile or the “…” menu on their post or comment."))
                    .font(DS.Font.plex(10.5, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .dsAlert(L10n.t("إلغاء الحظر", "Unblock Member"),
                 isPresented: Binding(get: { entryToUnblock != nil },
                                      set: { if !$0 { entryToUnblock = nil } }),
                 presenting: entryToUnblock) { entry in
            Button(L10n.t("إلغاء الحظر", "Unblock")) {
                store.unblock(entry)
                entryToUnblock = nil
            }
            Button(L10n.t("رجوع", "Back"), role: .cancel) { entryToUnblock = nil }
        } message: { entry in
            Text(L10n.t("ستظهر لك أخبار «\(entry.name)» وتعليقاته مرة أخرى.",
                        "Posts and comments from “\(entry.name)” will be visible to you again."))
        }
    }

    private func row(_ entry: BlockedMembersStore.Entry) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "person.crop.circle.badge.xmark", tint: DS.Color.error)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .dsFieldFont(13.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(L10n.t("محظور منذ \(Self.dateText(entry.blockedAt))",
                            "Blocked since \(Self.dateText(entry.blockedAt))"))
                    .font(DS.Font.plex(11))
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: DS.Spacing.xs)
            Button { entryToUnblock = entry } label: {
                Text(L10n.t("إلغاء الحظر", "Unblock"))
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 32)
                    .background(Capsule().fill(DS.Color.primary.opacity(0.12)))
                    // مساحة ضغط ٤٤ نقطة (توصية أبل) — الحبّة كما هي
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSScaleButtonStyle())
            .accessibilityLabel(L10n.t("إلغاء حظر \(entry.name)", "Unblock \(entry.name)"))
        }
        .dsRowBox()
    }

    private static func dateText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.isArabic ? "ar" : "en_US")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }
}
