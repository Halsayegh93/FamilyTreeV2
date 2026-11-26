import SwiftUI

// MARK: - «المنجز» (إعادة تصميم الإدارة ٢٠٢٦-١١-٢٦، الوحدة U8 — spec C.5)
//
// كان قسم «المنجزة» في مسار أقسام «الوارد» — صار صفحة يفتحها صفّ «المنجز» آخر «الوارد»: «‹ الوارد» · «المنجز» ·
// «آخر 30 يوماً، للاطلاع» ← البحث ← الأيام (اليوم · أمس · التاريخ)، كل يوم بطاقة من صفوفها بشكل صفوف «الوارد»: صورة مقدّم
// الطلب وعلى ركنها نوعه · الاسم والوقت · نوع الطلب والمعني به · حبّة النتيجة («قُبل» · «رُفض» · «نُفّذ» · «رُدّ» · «حُذف»)
// و«بواسطة فلان». الضغط يفتح مربّع الطلب للعرض فقط (يبنيه «الوارد»: نفس محتوى مربّع الطلبات + «ما تم في الطلب»)، وحذف
// الإدارة المباشر (§9) مربّعه `AdminDeletionBox`. لكل المشرفين، كلٌّ بمجاله (نفس قواعد ظهور «الطلبات»).
// المخزن واحد (`AdminHandledStore` في «الوارد») — رقم صفّ «المنجز» هو عدد هذه القائمة نفسها (T2).
// الحالات: هيكل · «لا شيء منجز في آخر 30 يوماً» · خطأ + «أعد المحاولة» (والقديم يبقى بـ«آخر تحديث»). للعرض فقط — لا كتابة.

struct AdminInboxHandledPage: View {
    @ObservedObject var store: AdminHandledStore
    /// مربّع الطلب المعالَج للعرض فقط — يبنيه «الوارد» (`handledBox`)؛ المعامل الثاني يغلقه
    let box: (AdminRequest, @escaping () -> Void) -> AnyView

    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @State private var search = ""
    @State private var open: AdminRequest?
    @State private var deletion: MemberDeletePlace?
    /// وقت آخر تحميل ناجح (المخزن لا يحفظه) — «آخر تحديث» والقديم بعد الفشل
    @State private var lastGood: Date?
    /// `-tmpFailStores inbox`: فشل مصطنع بلا جلب
    @State private var injectedFailure = false
    /// «ظهور موحّد»: الأيام تصعد مرة عند الظهور الأول
    @State private var appeared = false
    @Environment(\.adminBackTitle) private var outerBack

    static var title: String { L10n.t("المنجز", "Done") }

    var body: some View {
        AnyView(boxes(AnyView(page)))
            .debugStackProbe("AdminInboxHandledPage", limitKB: DebugStackLimit.page)
    }

    // MARK: ما يراه الدور (نفس مجالات «الطلبات» — المكان الواحد لـ«الوارد» وهذه الصفحة)

    /// الطلب المعالَج من مجال هذا الدور
    static func isVisible(_ r: AdminRequest, authVM: AuthViewModel) -> Bool {
        switch r.requestType {
        case "contact_message": return authVM.adminSees(.inboxMessages)
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue: return authVM.canModerateContent
        case RequestType.photoSuggestion.rawValue: return authVM.adminAccess(.inboxPhotos).canEdit && authVM.canModerateTree
        case RequestType.accountDelete.rawValue, RequestType.privacyRequest.rawValue,
             RequestType.relativeRemove.rawValue: return authVM.isAdmin
        default: return authVM.canModerateTree
        }
    }

    /// الطلبات المعالجة + حذف الإدارة المباشر في الأيام نفسها، الأحدث أولاً (§9) — بعد البحث
    @MainActor
    static func entries(store: AdminHandledStore, authVM: AuthViewModel, memberVM: MemberViewModel,
                        search: String) -> [AdminHandledEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var requests = store.items.filter { isVisible($0, authVM: authVM) }
        if !q.isEmpty {
            requests = requests.filter { r in
                let texts = [r.member?.fullName, memberVM.member(byId: r.requesterId)?.fullName, r.newValue, r.details,
                             AdminTrailText.typeTitle(r), r.treeEditPayload?.targetMemberName,
                             r.treeEditPayload?.newMemberName].compactMap { $0 }
                return NameSearch.matches(query: q, any: texts)
            }
        }
        var entries = requests.map(AdminHandledEntry.request)
        if authVM.canModerateTree {
            let deletions = store.deletions.filter { d in
                q.isEmpty || NameSearch.matches(query: q, any: [d.displayFullName, d.deletedByName ?? "", AdminDeletionText.title])
            }
            entries += deletions.map(AdminHandledEntry.deletion)
        }
        return entries.sorted { date($0, store: store) > date($1, store: store) }
    }

    /// وقت التجميع: وقت المعالجة، والقديم بلا وقت ردّ بوقت إرساله
    @MainActor
    static func date(_ entry: AdminHandledEntry, store: AdminHandledStore) -> Date {
        switch entry {
        case .request(let r):
            return DateHelper.parse(AdminTrailText.handledAt(r, events: store.events[r.id]))
                ?? DateHelper.parse(r.createdAt) ?? .distantPast
        case .deletion(let d):
            return d.deletedDate ?? .distantPast
        }
    }

    /// رقم صفّ «المنجز» في «الوارد»: العدد نفسه في هذه القائمة («+» حين بقي ما لم يُحمَّل) — nil قبل الوصول أو بعد الفشل
    @MainActor
    static func doorValue(store: AdminHandledStore, authVM: AuthViewModel, memberVM: MemberViewModel) -> String? {
        guard store.loadedOnce, !store.failed else { return nil }
        let n = entries(store: store, authVM: authVM, memberVM: memberVM, search: "").count
        return store.hasMore ? "\(DSNumber.grouped(n))+" : DSNumber.grouped(n)
    }

    // MARK: الحال

    private var health: AdminStoreHealth {
        if injectedFailure || store.failed { return .failed(lastGood: lastGood) }
        if store.loadedOnce { return .loaded(at: lastGood ?? Date()) }
        return .loading
    }

    private func reload() async {
        if DebugAdminProbe.shouldFail(.inbox, hasLoaded: store.loadedOnce) {   // `-tmpFailStores inbox`
            injectedFailure = true
            return
        }
        injectedFailure = false
        store.includesDeletions = authVM.canModerateTree
        await store.reload()
        if !store.failed { lastGood = Date() }
    }

    // MARK: الصفحة

    private func boxes(_ content: AnyView) -> some View {
        content
            .dsCenterBox(item: $open) { request in
                box(request) { open = nil }
            }
            .dsCenterBox(item: $deletion) { d in
                AnyView(AdminDeletionBox(deletion: d, men: memberVM.allMembers) { deletion = nil })
            }
    }

    private var page: some View {
        let visible = Self.entries(store: store, authVM: authVM, memberVM: memberVM, search: search)
        return AdminPage(header: AdminPageHeader(back: outerBack == nil ? AdminArea.inbox.title : nil,
                                                 title: Self.title,
                                                 subtitle: L10n.t("آخر 30 يوماً، للاطلاع", "Last 30 days, view only")),
                         lead: lead(visible),
                         layout: .list,
                         content: AnyView(rows(visible)),
                         updatedAt: health.lastGood)
            .refreshable { await reload() }
            .task {
                appeared = true
                // كل فتح يحدّث (قرار اتُّخذ للتوّ في «الوارد» يظهر هنا)
                await reload()
            }
    }

    /// البحث — مع وجود ما يُبحث فيه (لا فوق «لا شيء» ولا فوق خطأ)
    private func lead(_ visible: [AdminHandledEntry]) -> AnyView? {
        guard store.loadedOnce, !store.items.isEmpty || !store.deletions.isEmpty || !search.isEmpty else { return nil }
        return AnyView(DSSearchField(text: $search, placeholder: AdminFilterText.searchPlaceholder, style: .admin))
    }

    @ViewBuilder
    private func rows(_ visible: [AdminHandledEntry]) -> some View {
        let state = health
        if !store.loadedOnce && !injectedFailure {
            AnyView(DSCardSkeleton(style: .notice, count: 5, label: L10n.t("جارٍ تحميل المنجز…", "Loading what's done…")))
                .adminPageRow(top: DS.Hub.stackSpacing)
        } else if state.canRetry && visible.isEmpty && search.isEmpty {
            AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحميل المنجز", "Couldn't load what's done"),
                                              message: L10n.t("تحقّق من اتصالك ثم أعد المحاولة.",
                                                              "Check your connection, then try again."),
                                              retry: { Task { await reload() } }, lastGood: state.lastGood)))
                .adminPageRow(top: DS.Spacing.xs)
        } else {
            if state.canRetry {
                // التحديث فشل والقائمة القديمة باقية تحته
                AnyView(AdminPageStateCard(.error(L10n.t("تعذّر تحديث المنجز", "Couldn't refresh"),
                                                  message: L10n.t("تعرض آخر ما وصل.", "Showing the last list received."),
                                                  retry: { Task { await reload() } }, lastGood: state.lastGood)))
                    .adminPageRow(top: DS.Spacing.xs)
            }
            if visible.isEmpty {
                AnyView(emptyCard)
                    .adminPageRow(top: DS.Spacing.xs)
                if store.hasMore && search.isEmpty == false { moreButton }
            } else {
                ForEach(DSDayBuckets.group(visible) { Self.date($0, store: store) }) { day in
                    DSDayHeader(title: day.title, count: day.items.count)
                        .dsCardCascade(1, appeared: appeared)
                        .adminPageRow(top: DS.Hub.stackSpacing, bottom: DSNoticeMetrics.headerGap)
                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, entry in
                        cell(entry, position: DSGroupPosition(index: index, count: day.items.count))
                    }
                }
                if store.hasMore {
                    moreButton
                } else {
                    Text(L10n.t("آخر 30 يوماً", "Last 30 days"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .adminPageRow(top: DS.Spacing.md, bottom: 0)
                }
            }
        }
    }

    /// بحث بلا نتيجة: «لا نتائج» + «مسح البحث» (والباقي لم يُحمَّل: «اعرض المزيد»)؛ بلا بحث: «لا شيء منجز…»
    private var emptyCard: some View {
        Group {
            if !search.isEmpty {
                AdminPageStateCard(.empty(store.hasMore ? L10n.t("لا نتائج فيما حُمِّل", "No matches in what's loaded")
                                                        : L10n.t("لا نتائج", "No results"),
                                          message: store.hasMore
                                            ? L10n.t("اعرض المزيد لتبحث في الأقدم.", "Show more to search older ones.")
                                            : L10n.t("جرّب كلمة أخرى", "Try another word"),
                                          actionTitle: L10n.t("مسح البحث", "Clear search"),
                                          action: { search = "" }))
            } else {
                AdminPageStateCard(.empty(L10n.t("لا شيء منجز في آخر 30 يوماً", "Nothing done in the last 30 days"),
                                          message: L10n.t("الطلبات التي قُبلت أو رُفضت تظهر هنا.",
                                                          "Requests approved or rejected show here.")))
            }
        }
    }

    /// «عرض المزيد» — الصفحة التالية من المخزن
    private var moreButton: some View {
        Button {
            Task { await store.loadMore() }
        } label: {
            HStack(spacing: DS.Spacing.xs) {
                if store.isLoading {
                    ProgressView().scaleEffect(DS.Spinner.buttonScale)
                }
                Text(L10n.t("عرض المزيد", "Show more"))
            }
            .modifier(DSButtonFace(role: .cancel))
        }
        .buttonStyle(DSPressStyle())
        .disabled(store.isLoading)
        .adminPageRow(top: DS.Spacing.md, bottom: 0)
    }

    // MARK: الصفّ

    private func cell(_ entry: AdminHandledEntry, position: DSGroupPosition) -> some View {
        let model = rowModel(entry)
        return Button {
            switch entry {
            case .request(let r): open = r
            case .deletion(let d): deletion = d
            }
        } label: {
            AnyView(AdminInboxRow(model: model, position: position))
        }
        .buttonStyle(DSNoticePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(L10n.t("يعرض ما تم في الطلب", "Shows what happened"))
        .dsCardCascade(1, appeared: appeared)
        .adminPageRow(top: 0, bottom: 0)
    }

    private func rowModel(_ entry: AdminHandledEntry) -> AdminInboxRowModel {
        let events: [AdminRequestEvent]?
        if case .request(let r) = entry { events = store.events[r.id] } else { events = nil }
        return Self.rowModel(entry, events: events, date: Self.date(entry, store: store),
                             lookup: { memberVM.member(byId: $0) })
    }

    /// الصفّ من الطلب المعالَج وسجلّه — تقرؤه الصفحة ومعاينة التصميم (`-uiPreviewRequestTrail list`)
    @MainActor
    static func rowModel(_ entry: AdminHandledEntry, events: [AdminRequestEvent]?, date: Date,
                         lookup: (UUID) -> FamilyMember?) -> AdminInboxRowModel {
        let time = Self.clock(date)
        switch entry {
        case .request(let r):
            let decision = AdminTrailText.decision(r, events: events)
            let requester = lookup(r.requesterId) ?? (r.requesterId == r.memberId ? r.member : nil)
            let handler = AdminTrailText.handlerId(r, events: events).flatMap(lookup)?.firstName
            let about = Self.subject(r, lookup: lookup)
            let type = AdminTrailText.typeTitle(r)
            // «نوع الطلب — المعني به» إلا حين يكون المعني هو مقدّم الطلب نفسه (اسمه في العنوان)
            let ask = about.flatMap { $0 == requester?.fourPartName ? nil : "\(type) — \($0)" } ?? type
            return AdminInboxRowModel(
                name: requester?.fourPartName ?? about ?? L10n.t("عضو", "Member"),
                avatarName: requester?.firstName ?? "؟",
                avatarURL: requester?.avatarUrl,
                avatarTint: requester?.roleColor ?? DS.Color.brand,
                typeIcon: AdminTrailText.typeIcon(r),
                typeFill: DS.Color.primaryFill,
                time: time,
                ask: ask,
                pills: [AdminInboxRowModel.Pill(title: decision.title, tone: Self.tone(decision))],
                stateWord: L10n.t("بواسطة ", "By ") + (handler ?? AdminTrailText.notRecorded))
        case .deletion(let d):
            return AdminInboxRowModel(
                name: PersonName.firstThree(d.displayFullName),
                avatarName: d.displayFullName,
                avatarURL: nil,
                typeIcon: "person.badge.minus",
                typeFill: DS.Color.errorFill,
                time: time,
                ask: AdminDeletionText.title,
                pills: [AdminInboxRowModel.Pill(title: AdminDeletionText.chip, tone: .off)],
                stateWord: AdminDeletionText.by(d))
        }
    }

    /// المعني بالطلب: طلب شجرة النساء باسمه من الملاحظات، والإضافة بالاسم الجديد، وإلا العضو المستهدف
    @MainActor
    private static func subject(_ r: AdminRequest, lookup: (UUID) -> FamilyMember?) -> String? {
        let p = r.treeEditPayload
        if let women = p?.notes.flatMap(WomenTreeRequestLines.init) { return women.fullName }
        if p?.resolvedAction == .add, let name = p?.newMemberName, !name.isEmpty { return name }
        if let name = p?.targetMemberName, !name.isEmpty { return name }
        return r.member?.fourPartName ?? lookup(r.memberId)?.fourPartName
    }

    /// النتيجة بكلمتها ولونها (spec C.5): قُبل/نُفّذ نجاح · رُفض خطأ · رُدّ/عولج محايد
    private static func tone(_ d: AdminTrailText.Decision) -> AdminPillTone {
        switch d {
        case .approved, .executed: return .ok
        case .rejected:            return .error
        case .replied, .other:     return .off
        }
    }

    /// «8:40 ص» (اليوم في عنوان المجموعة)
    private static func clock(_ date: Date) -> String {
        AdminInboxClock.text(date)
    }
}
