import SwiftUI
import UIKit

// MARK: - حظر عضو (Guideline 1.2 — «حظر المستخدمين المسيئين»)
//
// `.dsBlockMemberFlow(target:)` — نفس رسائل «إبلاغ» الموحّدة (dsAlert): تأكيد الحظر ثم
// الحظر (BlockedMembersStore → `block_member` على السيرفر، والسيرفر نفسه يبلّغ الإدارة) + رسالة «تم الحظر».
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
    @ObservedObject private var store = BlockedMembersStore.shared
    /// اسم من حُظر للتو — يعرض «تم الحظر»
    @State private var blockedName: String?
    /// السيرفر رفض الحظر (عضو في الإدارة مثلاً) — أُلغي الحظر المحلي
    @State private var blockRefused = false

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
                    "لن تظهر لك أخبار «\(t.name)» ولا تعليقاته. لا يُبلَّغ العضو بأنك حظرته، وتقدر تلغي الحظر من الإعدادات ← الإشعارات والخصوصية.",
                    "You won't see posts or comments from “\(t.name)”. They won't be notified. You can unblock them from Settings → Notifications & Privacy."
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
                    "لن يظهر لك محتوى «\(blockedName ?? "")» بعد الآن. تقدر تلغي الحظر من الإعدادات ← الإشعارات والخصوصية.",
                    "You won't see content from “\(blockedName ?? "")” anymore. You can unblock them from Settings → Notifications & Privacy."
                ))
            }
            .dsAlert(L10n.t("تعذّر الحظر", "Couldn't Block"), isPresented: $blockRefused) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t("لا يمكن حظر هذا العضو. إن كان هناك إساءة فاستعمل «إبلاغ».",
                            "This member can't be blocked. If there's abuse, use “Report”."))
            }
    }

    private func block(_ t: BlockTarget) {
        // يُفرَّغ أولاً — وإلا تتحوّل الرسالة المفتوحة إلى «إلغاء الحظر» بعد الحظر مباشرة
        target = nil

        var ids = [t.id]
        var names = [t.name] + t.otherNames
        /// معرّف ملف العضو للسيرفر (`block_member`) — الملف إن عُرف، وإلا المعرّف كما وصل
        var profileId = t.id
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
                profileId = member.id
                names += [member.fullName, member.displayFullName]
            }
        }

        let me = authVM.currentUser
        let didBlock = store.block(
            ids: ids,
            names: names,
            selfIds: [me?.id, AccountIdentity.authUserId].compactMap { $0 },
            selfNames: [me?.fullName, me?.displayFullName].compactMap { $0 },
            primary: profileId
        )
        guard didBlock else { return }   // لا يحظر المستخدم نفسه أبداً

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let name = t.name
        // الحظر على السيرفر — السيرفر نفسه يرفع البلاغ للإدارة ويُشعرها (لا بلاغ من التطبيق، ٢٠٢٦-١٠-٢٩)
        Task {
            let result = await store.blockOnServer(profileId)
            if result == .notAllowed || result == .selfBlock {
                blockedName = nil
                blockRefused = true
            }
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
    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var entryToUnblock: BlockedMembersStore.Entry?

    /// الاسم المحفوظ، أو اسمه من الشجرة لمدخل وصل من السيرفر بلا اسم
    private func name(_ entry: BlockedMembersStore.Entry) -> String {
        if !entry.name.isEmpty { return entry.name }
        return memberVM.member(byId: entry.id)?.displayFullName ?? L10n.t("عضو", "Member")
    }

    var body: some View {
        DSComposerSection(title: L10n.t("الأعضاء المحظورون", "Blocked Members"),
                          icon: "hand.raised.fill",
                          tint: DS.Color.error,
                          trailing: store.entries.isEmpty ? nil : "\(store.entries.count)",
                          index: index) {
            VStack(spacing: DS.Spacing.sm) {
                if store.entries.isEmpty {
                    // الحالة الفاضية الواحدة (مضغوطة داخل القسم)
                    DSEmptyView(L10n.t("لا يوجد أعضاء محظورون", "No blocked members"),
                                icon: "hand.raised.slash.fill", style: .inline)
                } else {
                    ForEach(store.entries) { entry in
                        row(entry)
                    }
                }
                Text(L10n.t("المحظور لا تظهر لك أخباره ولا تعليقاته، ولا يُبلَّغ بأنك حظرته. تحظر العضو من ملفه أو من قائمة «…» على خبره أو تعليقه.",
                            "You won't see posts or comments from blocked members, and they aren't notified. Block someone from their profile or the “…” menu on their post or comment."))
                    .dsFont(.footnoteCompact)
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
            Text(L10n.t("ستظهر لك أخبار «\(name(entry))» وتعليقاته مرة أخرى.",
                        "Posts and comments from “\(name(entry))” will be visible to you again."))
        }
    }

    private func row(_ entry: BlockedMembersStore.Entry) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "person.crop.circle.badge.xmark", tint: DS.Color.error)
                .accessibilityHidden(true)   // زخرفة
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(name(entry))
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .dsNameLines()
                if entry.hasDate {
                    Text(L10n.t("محظور منذ \(Self.dateText(entry.blockedAt))",
                                "Blocked since \(Self.dateText(entry.blockedAt))"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            // الشريحة الواحدة (لون القسم)
            DSChipButton(L10n.t("إلغاء الحظر", "Unblock")) { entryToUnblock = entry }
                .fixedSize()
                .accessibilityLabel(L10n.t("إلغاء حظر \(name(entry))", "Unblock \(name(entry))"))
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
