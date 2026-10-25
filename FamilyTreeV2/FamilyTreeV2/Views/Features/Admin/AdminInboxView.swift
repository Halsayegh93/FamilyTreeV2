import SwiftUI
import Supabase

/// قائمة رسائل التواصل من الأعضاء — نموذج بسيط (لا دردشة).
/// كل صف = رسالة واحدة. الضغط يفتح تفاصيلها مع خيارات الرد بالاتصال/واتساب.
///
/// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بلون بلاطة «الرسائل» في لوحة
/// الإدارة وأرقامها الحيّة ← بحث + فلترا الحالة بعددهما ← صفوف `.dsRowBox()` (صورة المرسل · الاسم
/// والوقت · مقتطف الرسالة · التصنيف والحالة). السحب («حذف» / «تمّت المعالجة»)، التحديد المتعدد والحذف
/// وتأكيداتهما، السحب للتحديث، ومربّع التفاصيل كما كانت تماماً.
struct AdminInboxView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    /// داخل «الوارد» (إعادة تصميم اللوحة ٢٠٢٦-١٠-٢٠): بلا رأس خاص — رأس «الوارد» فوقها، و«تحديد» شريحة أعلى المحتوى
    var embedded: Bool = false
    /// بحث «الوارد» الواحد (الدفعة ب ٢٠٢٦-١٠-٢٠): نفس النص يبحث في الطلبات والرسائل — nil = بحث الصفحة الخاص
    var sharedSearch: Binding<String>? = nil

    /// تلميح حقل البحث الواحد في «الوارد» (الطلبات والرسائل)
    static let searchPlaceholder = L10n.t("بحث في الطلبات والرسائل بالاسم أو الرقم", "Search requests and messages by name or number")

    @State private var ownSearch: String = ""
    private var searchBinding: Binding<String> { sharedSearch ?? $ownSearch }
    private var searchText: String { searchBinding.wrappedValue }
    @State private var isLoading = false
    @State private var selectedMessage: AdminRequest? = nil
    @State private var filter: InboxFilter = .pending
    /// نوع الرسالة المختار (استفسار، اقتراح، شكوى، أخرى) — `allKinds` = الكل
    @State private var kind: String = AdminInboxView.allKinds
    static let allKinds = "*"
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    /// رسالة طُلب حذفها بالسحب — تأكيد قبل الحذف
    @State private var messageToDelete: AdminRequest? = nil
    /// اكتمل أول جلب — قبله «—» في الأرقام وبطاقة تحميل (إن لم تكن هناك رسائل محمّلة أصلاً)
    @State private var hasLoaded = false
    /// آخر جلب انتهى والجهاز غير متصل — لبطاقة «تعذّر التحميل» بدل «ما فيه رسائل» المضلِّلة
    /// (تبقى حتى جلب ناجح: السحب للتحديث أو «إعادة المحاولة»)
    @State private var lastFetchOffline = false
    /// دخول صفوف الرسائل (نمط الأخبار والديوانيات) — مرة واحدة حين تظهر القائمة
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// لون بلاطة «الرسائل» في لوحة الإدارة — رأس الصفحة يطابق البلاطة التي ضُغطت
    private let pageTint = DS.Color.composerDiwaniya

    private enum InboxFilter: String, CaseIterable {
        case pending, handled
        var title: String {
            switch self {
            case .pending: return L10n.t("لم تُعالَج بعد", "Pending")
            case .handled: return L10n.t("تمّت المعالجة", "Handled")
            }
        }
        var icon: String {
            switch self {
            case .pending: return "clock.fill"
            case .handled: return "checkmark.circle.fill"
            }
        }
        /// لون الحالة: منتظر = تحذير، تم = نجاح
        var color: Color {
            switch self {
            case .pending: return DS.Color.warning
            case .handled: return DS.Color.success
            }
        }
    }

    /// الحالة المختارة + البحث (قبل فلتر النوع — منها أعداد شرائح الأنواع)
    private var statusMessages: [AdminRequest] {
        let all = adminRequestVM.contactMessages
        let byStatus: [AdminRequest]
        switch filter {
        case .pending: byStatus = all.filter { $0.status == ApprovalStatus.pending.rawValue }
        case .handled: byStatus = all.filter { $0.status == ApprovalStatus.approved.rawValue }
        }
        let sorted = byStatus.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return sorted }
        // نفس مطابقة بحث الطلبات: الاسم أو النص بلا تشكيل/همزات، أو الرقم (٣ أرقام فأكثر)
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب (والرقم أرقاماً فقط)
        if NameSearch.isPhoneQuery(q) {
            return sorted.filter { NameSearch.phoneMatches(query: q, phone: $0.member?.phoneNumber) }
        }
        return sorted.filter { msg in
            NameSearch.matches(query: q, any: [msg.member?.fullName ?? "", ContactParser.message(from: msg)])
        }
    }

    /// أنواع الرسائل في الحالة المختارة بعددها (الأكثر أولاً) — شرائح النوع تظهر حين يكون فيها نوعان فأكثر
    private func kindCounts(_ messages: [AdminRequest]) -> [(info: ContactCategoryInfo, count: Int)] {
        var order: [String] = []
        var map: [String: (info: ContactCategoryInfo, count: Int)] = [:]
        for msg in messages {
            let info = ContactCategoryInfo.from(raw: ContactParser.category(of: msg))
            if map[info.title] == nil { order.append(info.title); map[info.title] = (info, 0) }
            map[info.title]?.count += 1
        }
        return order.compactMap { map[$0] }.sorted { $0.count > $1.count }
    }

    /// النوع المختار إن كان موجوداً في الحالة الحالية، وإلا «الكل»
    private func activeKind(_ kinds: [(info: ContactCategoryInfo, count: Int)]) -> String {
        kinds.contains { $0.info.title == kind } ? kind : Self.allKinds
    }

    /// عدد الرسائل في كل حالة (نفس أعداد التبويبين السابقين) — مرور واحد على الرسائل
    private var statusCounts: [InboxFilter: Int] {
        var counts: [InboxFilter: Int] = [:]
        for msg in adminRequestVM.contactMessages {
            if msg.status == ApprovalStatus.pending.rawValue {
                counts[.pending, default: 0] += 1
            } else if msg.status == ApprovalStatus.approved.rawValue {
                counts[.handled, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - حالة التحميل

    /// أول تحميل (أو «إعادة المحاولة») ولا رسائل محمّلة بعد
    private var isInitialLoading: Bool {
        (isLoading || !hasLoaded) && adminRequestVM.contactMessages.isEmpty
    }

    /// الجلب انتهى بلا رسائل والجهاز غير متصل — القائمة الفارغة هنا ليست «ما فيه رسائل»
    private var loadFailed: Bool {
        hasLoaded && !isLoading && adminRequestVM.contactMessages.isEmpty && lastFetchOffline
    }

    /// نفس الجلب السابق تماماً (`fetchContactMessages`) — ويحفظ هل انتهى بلا اتصال
    private func loadMessages(force: Bool = false) async {
        await adminRequestVM.fetchContactMessages(force: force)
        lastFetchOffline = !NetworkMonitor.shared.isConnected
    }

    /// «إعادة المحاولة» — نفس تحميل الفتح (مع بطاقة التحميل)
    private func retryLoad() async {
        isLoading = true
        await loadMessages(force: true)
        isLoading = false
    }

    // MARK: - Body

    // حارس المكدس (الدفعة ب ٢٠٢٦-١٠-٢٠): الصفحة ثم التأكيدات والمربّع طبقتان خلف `AnyView`
    var body: some View {
        AnyView(dialogsLayer(AnyView(pageLayer)))
    }

    private var pageLayer: some View {
        let status = statusMessages
        let kinds = kindCounts(status)
        let selected = activeKind(kinds)
        let messages = selected == Self.allKinds ? status
            : status.filter { ContactCategoryInfo.from(raw: ContactParser.category(of: $0)).title == selected }
        let counts = statusCounts

        // صفّ الأرقام ← البحث والفلاتر ← الرسائل: تتمرّر معاً (والسحب للتحديث يعمل حتى والقائمة فارغة)
        return ScrollView(showsIndicators: false) {
            AnyView(pageContent(messages: messages, counts: counts, kinds: kinds, selectedKind: selected))
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await loadMessages(force: true) }
        // شريط الحذف السفلي في وضع التحديد — مثبّت، وآخر رسالة تبقى فوقه
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectMode {
                deleteBar
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        // الرأس الملوّن الموحّد — «تحديد» (كان في شريط النظام) زرّ الرأس؛ داخل «الوارد» بلا رأس
        .modifier(InboxHeader(embedded: embedded, hasMessages: !messages.isEmpty, isSelectMode: isSelectMode,
                              toggleSelect: toggleSelectMode))
    }

    /// تأكيدا الحذف، والتحميل الأول، ومربّع تفاصيل الرسالة
    private func dialogsLayer(_ content: AnyView) -> some View {
        content
        .dsAlert(L10n.t("حذف الرسائل", "Delete Messages"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task { await deleteSelected() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد حذف \(selectedIDs.count) رسالة؟ لا يمكن التراجع.",
                        "Delete \(selectedIDs.count) message(s)? This can't be undone."))
        }
        .dsAlert(L10n.t("حذف الرسالة", "Delete Message"), isPresented: Binding(
            get: { messageToDelete != nil },
            set: { if !$0 { messageToDelete = nil } }
        )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let m = messageToDelete {
                    Task { await adminRequestVM.deleteContactMessages(ids: [m.id]) }
                }
                messageToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { messageToDelete = nil }
        } message: {
            Text(L10n.t("هل تريد حذف هذه الرسالة؟ لا يمكن التراجع.", "Delete this message? This can't be undone."))
        }
        .task {
            isLoading = true
            await loadMessages()
            isLoading = false
            withAnimation(reduceMotion ? nil : DS.Anim.smooth) { hasLoaded = true }
        }
        .dsCenterBox(item: $selectedMessage) { msg in
            MessageDetailSheet(message: msg) {
                selectedMessage = nil
            }
        }
    }

    private func toggleSelectMode() {
        withAnimation(DS.Anim.quick) {
            isSelectMode.toggle()
            if !isSelectMode { selectedIDs.removeAll() }
        }
    }

    // MARK: - هيكل الصفحة

    private func pageContent(messages: [AdminRequest], counts: [InboxFilter: Int],
                             kinds: [(info: ContactCategoryInfo, count: Int)], selectedKind: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            if !embedded {
                // داخل «الوارد»: الأرقام في رأسه، و«تحديد» في طرف شرائح الحالة (أدناه)
                heroSection(counts: counts)
            }

            if isInitialLoading {
                DSPageLoader(L10n.t("جارٍ تحميل الرسائل…", "Loading messages…"), fillsSpace: false)
                    .padding(.top, DS.Spacing.xl)
                    .dsStaggerIn(1)
            } else if loadFailed {
                DSStateCard(icon: "wifi.exclamationmark",
                             title: L10n.t("تعذّر تحميل الرسائل", "Couldn't load messages"),
                             hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                             tint: DS.Color.error,
                             actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                             action: { Task { await retryLoad() } })
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(1)
            } else {
                DSSearchField(text: searchBinding,
                              placeholder: sharedSearch == nil ? L10n.t("ابحث…", "Search…") : Self.searchPlaceholder,
                              tint: pageTint)
                    .dsStaggerIn(1)

                // شرائح الحالة، و«تحديد» في طرفها داخل «الوارد» (كان سطراً وحده فوق البحث) — وفوقها في سطرها إن ضاق
                // السطر (خط الجهاز الأكبر)
                if embedded && !messages.isEmpty {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: DS.Spacing.sm) {
                            filterChips(counts)
                            selectChip
                        }
                        VStack(alignment: .trailing, spacing: DS.Spacing.xs) {
                            selectChip
                            filterChips(counts)
                        }
                    }
                    .dsStaggerIn(1)
                } else {
                    filterChips(counts)
                        .dsStaggerIn(1)
                }

                // شرائح النوع (استفسار · اقتراح · شكوى · أخرى) حين يكون في الحالة المختارة نوعان فأكثر
                if kinds.count >= 2 {
                    kindChips(kinds, selected: selectedKind)
                        .dsStaggerIn(1)
                }

                if messages.isEmpty {
                    emptyState(counts: counts)
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(2)
                } else {
                    if adminRequestVM.unreadContactMessagesCount > 0 {
                        markAllReadBar
                            .dsStaggerIn(2)
                    }

                    // بالأيام (طلب المالك ٢٠٢٦-١٠-٢٤ «ابي ارتبها»): اليوم · أمس · التاريخ — كل يوم بطاقة واحدة بصفوف مختصرة،
                    // وكل بطاقة تصعد مرة عند الظهور (أول ٧، وما يُبنى بالتمرير يظهر مباشرة)
                    LazyVStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
                        let days = DSDayBuckets.group(messages) { ContactParser.date($0.createdAt) ?? .distantPast }
                        ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                            VStack(alignment: .leading, spacing: DSNoticeMetrics.headerGap) {
                                DSDayHeader(title: day.title, count: day.items.count)
                                VStack(spacing: 0) {
                                    ForEach(Array(day.items.enumerated()), id: \.element.id) { index, msg in
                                        messageCell(msg, position: DSGroupPosition(index: index, count: day.items.count))
                                    }
                                }
                            }
                            .dsCardCascade(dayIndex, appeared: appeared)
                        }
                    }
                    .onAppear(perform: startRowsCascade)
                }
            }
        }
    }

    /// «تحديد» / «تم» داخل «الوارد»
    private var selectChip: some View {
        DSChipButton(isSelectMode ? L10n.t("تم", "Done") : L10n.t("تحديد", "Select"),
                     icon: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle",
                     isSelected: isSelectMode, size: .small, action: toggleSelectMode)
            .fixedSize()
    }

    /// شرائح نوع الرسالة بعددها — «الكل» أولاً ثم الأنواع الموجودة (الأكثر أولاً) بأيقونة كل نوع
    private func kindChips(_ kinds: [(info: ContactCategoryInfo, count: Int)], selected: String) -> some View {
        let total = kinds.reduce(0) { $0 + $1.count }
        let options = [DSFilterOption(id: Self.allKinds, title: L10n.t("كل الأنواع", "All kinds"), count: total)]
            + kinds.map { DSFilterOption(id: $0.info.title, title: $0.info.title, icon: $0.info.icon, count: $0.count) }
        return DSFilterChips(options: options,
                             selection: Binding(get: { selected }, set: { kind = $0 }),
                             tint: pageTint)
    }

    /// الصفوف تدخل بعد أقسام الصفحة فوقها (البحث والفلاتر ← العنوان = ٢) — من حيث كانت تبدأ (٣)،
    /// فيبقى التسلسل: الرأس ← الأقسام ← الصفوف. مرة واحدة؛ «تقليل الحركة»: تلاشٍ فوري بلا انتظار.
    private func startRowsCascade() {
        guard !appeared else { return }
        guard !reduceMotion else { appeared = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotion.staggerDelay(3, base: DSMotion.sectionsOnPage)) {
            appeared = true
        }
    }

    // MARK: - بطاقة الرأس

    private func heroSection(counts: [InboxFilter: Int]) -> some View {
        // العنوان والوصف في الرأس الملوّن — الأرقام هنا
        DSStatsRow(heroStats(counts: counts), tint: pageTint)
    }

    /// ٣ أرقام حيّة من الرسائل المحمّلة أصلاً (بلا طلبات جديدة للسيرفر): غير المقروءة، ما ينتظر
    /// الرد، وما وصل اليوم — «—» قبل اكتمال أول تحميل.
    private func heroStats(counts: [InboxFilter: Int]) -> [DSHeroStat] {
        let unreadLabel = L10n.t("غير مقروءة", "Unread")
        let pendingLabel = L10n.t("بانتظار الرد", "Awaiting reply")
        let todayLabel = L10n.t("جديد اليوم", "New today")

        guard !isInitialLoading, !loadFailed else {
            return [
                DSHeroStat(value: "—", label: unreadLabel, icon: "envelope.badge.fill"),
                DSHeroStat(value: "—", label: pendingLabel, icon: "clock.fill"),
                DSHeroStat(value: "—", label: todayLabel, icon: "sparkles")
            ]
        }

        let calendar = Calendar.current
        let today = adminRequestVM.contactMessages.filter { msg in
            guard let date = ContactParser.date(msg.createdAt) else { return false }
            return calendar.isDateInToday(date)
        }.count

        return [
            DSHeroStat(value: "\(adminRequestVM.unreadContactMessagesCount)",
                       label: unreadLabel, icon: "envelope.badge.fill"),
            DSHeroStat(value: "\(counts[.pending] ?? 0)", label: pendingLabel, icon: "clock.fill"),
            DSHeroStat(value: "\(today)", label: todayLabel, icon: "sparkles")
        ]
    }

    // MARK: - الفلاتر

    /// نفس التبويبين السابقين («لم يتم التعامل» / «تم التعامل») — العدد يظهر فقط إذا أكبر من صفر
    private func filterChips(_ counts: [InboxFilter: Int]) -> some View {
        DSFilterChips(
            options: InboxFilter.allCases.map { f in
                let n = counts[f] ?? 0
                return DSFilterOption(id: f, title: f.title, icon: f.icon, count: n > 0 ? n : nil)
            },
            selection: $filter,
            tint: pageTint
        )
    }

    // MARK: - Swipe actions

    private func swipeActions(for msg: AdminRequest) -> [DSSwipeAction] {
        var actions = [
            DSSwipeAction(icon: "trash.fill", title: L10n.t("حذف", "Delete"), color: DS.Color.errorFill) {
                messageToDelete = msg
            }
        ]
        if msg.status == ApprovalStatus.pending.rawValue {
            actions.append(DSSwipeAction(icon: "checkmark.circle.fill", title: L10n.t("تمّت المعالجة", "Handled"),
                                         color: DS.Color.successFill) {
                adminRequestVM.markContactMessageRead(msg.id)
                Task { await adminRequestVM.markContactMessageHandled(msg) }
            })
        }
        return actions
    }

    // MARK: - Select / Delete

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func deleteSelected() async {
        isDeleting = true
        await adminRequestVM.deleteContactMessages(ids: Array(selectedIDs))
        selectedIDs.removeAll()
        isDeleting = false
        withAnimation(DS.Anim.quick) { isSelectMode = false }
    }

    /// شريط وضع التحديد: العدد · «حذف» (يسأل قبل الحذف)
    private var deleteBar: some View {
        HStack(spacing: DS.Spacing.md) {
            Text(L10n.t("\(selectedIDs.count) محدّدة", "\(selectedIDs.count) selected"))
                .dsFieldFont(.rowTitle)
                .foregroundColor(DS.Color.fieldValue)
                .monospacedDigit()
            Spacer()
            // الزرّ الواحد بالأحمر (دوّارته داخله أثناء الحذف)
            DSButton(L10n.t("حذف", "Delete"), icon: "trash.fill", role: .destructive,
                     isLoading: isDeleting, fullWidth: false) {
                showDeleteConfirm = true
            }
            .disabled(selectedIDs.isEmpty || isDeleting)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .dsGlass(Rectangle())
        .overlay(Divider(), alignment: .top)
    }

    // MARK: - الحالة الفارغة

    /// لا رسائل في الحالة المختارة (أو لا نتيجة للبحث) — وزر يفتح الحالة الأخرى إن كان فيها رسائل
    @ViewBuilder
    private func emptyState(counts: [InboxFilter: Int]) -> some View {
        let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if searching {
            DSEmptyView(L10n.t("لا توجد نتائج", "No results"),
                        message: L10n.t("جرّب كلمة أخرى", "Try another word"),
                        style: .compact)
        } else {
            let other: InboxFilter = filter == .pending ? .handled : .pending
            let otherCount = counts[other] ?? 0
            let showOther: (() -> Void)? = otherCount > 0 ? { showFilter(other) } : nil
            DSEmptyView(L10n.t("ما فيه رسائل", "No messages"),
                        message: filter == .pending
                            ? L10n.t("تمّت معالجة كل الرسائل", "All messages handled")
                            : L10n.t("لا توجد رسائل متعامل معها بعد", "No handled messages yet"),
                        tint: filter == .pending ? DS.Color.success : nil,
                        actionTitle: otherCount > 0
                            ? L10n.t("عرض «\(other.title)» (\(otherCount))", "Show \(other.title) (\(otherCount))")
                            : nil,
                        actionIcon: other.icon,
                        style: .compact, action: showOther)
        }
    }

    private func showFilter(_ f: InboxFilter) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { filter = f }
    }

    // MARK: - Row

    /// الخلية: صفّ الرسالة في بطاقة يومه (موضعه منها) — دائرة التحديد داخله في وضع التحديد.
    /// ضغطة فعلية فقط تفتح التفاصيل — السحب لا يفتحها (طلب المالك).
    /// (زر Button كان يعدّ رفع الإصبع بعد السحب ضغطة)
    private func messageCell(_ msg: AdminRequest, position: DSGroupPosition) -> some View {
        let picked = selectedIDs.contains(msg.id)
        let isUnread = !adminRequestVM.readContactMessageIds.contains(msg.id)
        let actions = isSelectMode ? [] : swipeActions(for: msg)

        return messageRow(msg, isUnread: isUnread, picked: picked, position: position)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectMode {
                toggleSelection(msg.id)
            } else {
                adminRequestVM.markContactMessageRead(msg.id)
                selectedMessage = msg
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? L10n.t("جديدة", "New") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelectMode && picked ? .isSelected : [])
        // نفس أزرار السحب للقارئ الصوتي (لا يسحب البطاقة) — نفس الإجراءات تماماً
        .accessibilityActions {
            ForEach(actions) { action in
                Button(action.title) { action.action() }
            }
        }
        // نفس سحب الأخبار: صوب اليمين يكشف «حذف» و«تم التعامل» (طلب المالك)
        .dsSwipeActions(id: msg.id, actions: actions)
    }

    /// صفّ مختصر (`DSNoticeRow`، طلب المالك ٢٠٢٦-١٠-٢٤ «ابي ارتبها»): صورة المرسل وعلى ركنها أيقونة نوع الرسالة بلونه ·
    /// الاسم (سطران — طلب المالك) وفي طرفه الوقت ونقطة «جديد» الذهبية · مقتطف الرسالة · النوع بلونه. الحالة (بانتظار الرد /
    /// تمّت المعالجة) هي شريحة الفلتر فوق — لا تتكرّر في كل صفّ
    private func messageRow(_ msg: AdminRequest, isUnread: Bool, picked: Bool, position: DSGroupPosition) -> some View {
        let info = ContactCategoryInfo.from(raw: ContactParser.category(of: msg))
        let preview = ContactParser.message(from: msg)
        let date = ContactParser.date(msg.createdAt)

        return DSNoticeRow(title: msg.member?.displayFullName ?? L10n.t("عضو", "Member"),
                           time: date.map(relativeShort) ?? "", unread: isUnread, tint: AppSection.admin.ink) {
            HStack(spacing: DSNoticeMetrics.selectGap) {
                if isSelectMode {
                    DSNoticeSelectCircle(picked: picked, tint: AppSection.admin.ink)
                }
                avatar(for: msg.member, kind: info)
            }
        } detail: {
            if !preview.isEmpty {
                DSNoticeText(text: preview, unread: isUnread, role: .subtitle)
            }
            kindLabel(info)
        }
        .dsGroupedRow(position, radius: DS.Hub.cardRadius,
                      dividerInset: DSNoticeMetrics.dividerInset(icon: DS.Icon.avatarRow, selecting: isSelectMode),
                      highlight: isSelectMode && picked ? AppSection.admin.ink.opacity(DS.Opacity.tintFill) : nil)
    }

    /// نوع الرسالة بلونه تحت المقتطف (أيقونة صغيرة + الاسم)
    private func kindLabel(_ info: ContactCategoryInfo) -> some View {
        Label {
            Text(info.title).dsFont(.badge).lineLimit(1)
        } icon: {
            Image(dsSymbol: info.icon).dsGlyph(DS.Glyph.micro)
        }
        .labelStyle(DSNoticeMetaLabelStyle())
        .foregroundColor(info.color.dsReadableGlyph)
    }

    // MARK: - Mark all read bar

    /// «● 7 رسائل جديدة … قراءة الكل» — سطر خفيف فوق الأيام (كان صندوقاً بأيقونة): النقطة الذهبية نفسها التي على
    /// الرسائل الجديدة، ونفس «تحديد الكل كمقروء»
    private var markAllReadBar: some View {
        let unread = adminRequestVM.unreadContactMessagesCount
        let text = L10n.isArabic
            ? AdminTodayText.arabicCount(unread, one: "رسالة جديدة", two: "رسالتان جديدتان", few: "رسائل جديدة",
                                         many: "رسالة جديدة", single: "رسالة جديدة")
            : (unread == 1 ? "1 new message" : "\(unread) new messages")
        return HStack(spacing: DS.Spacing.sm) {
            DSGoldDot(size: DSNoticeMetrics.unreadDot)
            Text(verbatim: text)
                .dsFont(.hubLabel)
                .monospacedDigit()
                .foregroundColor(DS.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            DSChipButton(L10n.t("تحديد الكل كمقروء", "Mark all read"), icon: "envelope.open.fill", size: .small) {
                withAnimation(DS.Anim.quick) {
                    adminRequestVM.markAllContactMessagesRead()
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, DS.Spacing.xs)
        .accessibilityElement(children: .contain)
    }

    /// صورة المرسل — وعلى ركنها أيقونة نوع الرسالة بتعبئته (رمز أبيض بحلقة بلون السطح)
    private func avatar(for member: FamilyMember?, kind info: ContactCategoryInfo) -> some View {
        DSMemberAvatar(
            name: member?.firstName ?? "?",
            avatarUrl: member?.avatarUrl,
            size: DS.Icon.avatarRow,
            roleColor: member?.roleColor ?? DS.Color.primary
        )
        .overlay(alignment: .bottomTrailing) {
            Image(dsSymbol: info.icon)
                .dsGlyph(DSNoticeMetrics.kindBadgeGlyph, weight: .bold)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DSNoticeMetrics.kindBadge, height: DSNoticeMetrics.kindBadge)
                .background(Circle().fill(Self.kindFill(info)))
                .overlay(Circle().strokeBorder(DS.Color.surface, lineWidth: DS.Border.widthBold))
                .offset(x: L10n.isArabic ? -DS.Spacing.xs : DS.Spacing.xs, y: DS.Spacing.xs)
        }
        .accessibilityHidden(true)
    }

    /// تعبئة ثابتة تحت الرمز الأبيض لكل نوع (لا تفتح في الداكن)
    private static func kindFill(_ info: ContactCategoryInfo) -> Color {
        if info.color == DS.Color.sadu { return DS.Color.saduFill }
        if info.color == DS.Color.palm { return DS.Color.palmFill }
        if info.color == DS.Color.accent { return DS.Color.goldFill }
        if info.color == DS.Color.textSecondary { return DS.Color.slateFill }
        return DS.Color.primaryFill
    }

    private func relativeShort(_ d: Date) -> String {
        let secs = Int(Date().timeIntervalSince(d))
        if secs < 60 { return L10n.t("الآن", "Now") }
        if secs < 3600 { return L10n.t("\(secs/60) د", "\(secs/60)m") }
        if secs < 86400 { return L10n.t("\(secs/3600) س", "\(secs/3600)h") }
        if secs < 604800 { return L10n.t("\(secs/86400) ي", "\(secs/86400)d") }
        let df = DateFormatter()
        df.dateFormat = "d MMM"
        df.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en")
        return df.string(from: d)
    }
}

// MARK: - Message Detail Sheet

/// تفاصيل الرسالة — مربّع عرض بنفس التصميم الموحّد (طلب المالك): المرسل، الرسالة،
/// الرد على العضو، و«تم التعامل» (للرسالة المعلّقة) / «إغلاق» أسفل المربّع
private struct MessageDetailSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    let message: AdminRequest
    let onDismiss: () -> Void

    @State private var isMarking = false
    /// مربّع كتابة الرد الرسمي (يُرسل من بريد العائلة)
    @State private var showEmailComposer = false

    private var isPending: Bool { message.status == ApprovalStatus.pending.rawValue }

    var body: some View {
        DSComposer(
            title: L10n.t("تفاصيل الرسالة", "Message Detail"),
            subtitle: message.member?.displayFullName ?? L10n.t("عضو", "Member"),
            icon: "envelope.open.fill",
            tint: DS.Color.actionNavy,
            actionTitle: isMarking ? L10n.t("جارٍ…", "Working…") : L10n.t("تمّت المعالجة", "Mark as Handled"),
            actionIcon: "checkmark.circle.fill",
            showsAction: isPending,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: true,
            isBusy: isMarking,
            isBehindExtra: showEmailComposer,
            onSubmit: { Task { await markHandled() } },
            onCancel: onDismiss
        ) {
            senderSection
            messageSection
            replySection
        }
        .onAppear {
            // defensive: تأكد أن الرسالة معلّمة كمقروءة حتى لو فُتحت من مسار آخر
            adminRequestVM.markContactMessageRead(message.id)
        }
        .dsCenterBox(isPresented: $showEmailComposer) {
            OfficialReplySheet(
                to: ContactParser.preferredContact(from: message) ?? "",
                memberName: message.member?.displayFullName ?? "",
                category: ContactParser.category(of: message),
                originalMessage: ContactParser.message(from: message)
            )
        }
    }

    // MARK: المرسل — الصورة · الاسم والهاتف · التصنيف في الطرف المقابل

    private var senderSection: some View {
        let info = ContactCategoryInfo.from(raw: ContactParser.category(of: message))
        let phone = message.member?.phoneNumber ?? ""
        return DSComposerSection(title: L10n.t("المرسل", "Sender"),
                                 icon: "person.fill",
                                 tint: AppSection.admin.ink,
                                 index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(
                    name: message.member?.firstName ?? "?",
                    avatarUrl: message.member?.avatarUrl,
                    size: DS.Icon.avatar,
                    roleColor: message.member?.roleColor ?? DS.Color.primary
                )
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(message.member?.displayFullName ?? L10n.t("عضو", "Member"))
                        .dsFont(.headlineCompact)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !phone.isEmpty {
                        Text(phone)
                            .dsFieldFont(.subtitle)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: DS.Spacing.xxs) {
                    // التصنيف يُقرأ من النص تحته — قرص الحالة المجسّم بلون التصنيف كما هو
                    DSStateIcon(info.icon, tint: info.color, size: DS.Icon.row, mapsChrome: false)
                    Text(info.title)
                        .dsFont(.micro)
                        .foregroundColor(DS.Color.textSecondary)
                }
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)   // المرسل ورقمه وتصنيف الرسالة معاً
        }
    }

    // MARK: نص الرسالة (+ حالة التعامل)

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الرسالة", "Message"),
                          icon: "text.bubble.fill",
                          tint: DS.Color.info,
                          index: 1) {
            Text(ContactParser.message(from: message))
                .dsFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsRowBox()

            if !isPending {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "checkmark.seal.fill", tint: DS.Color.success)
                        .accessibilityHidden(true)
                    Text(L10n.t("تمّت معالجة هذه الرسالة", "This message was handled"))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.success)
                    Spacer(minLength: 0)
                }
                .dsRowBox()
            }
        }
    }

    // MARK: الرد على العضو — الوسيلة التي طلبها العضو أوّلاً، ثم رقمه المسجّل

    @ViewBuilder
    private var replySection: some View {
        let phone = message.member?.phoneNumber ?? ""
        let preferred = ContactParser.preferredContact(from: message)
        let isEmail = (preferred ?? "").contains("@")
        let replyPhone = isEmail ? phone : (preferred ?? phone)

        if isEmail || !replyPhone.isEmpty {
            DSComposerSection(title: L10n.t("الرد على العضو", "Reply to member"),
                              icon: "arrowshape.turn.up.left.fill",
                              tint: DS.Color.success,
                              index: 2) {
                // وسيلة التواصل التي كتبها العضو — تُعرض وتُنسخ بالضغط
                if let preferred {
                    preferredContactRow(preferred, isEmail: isEmail)
                }

                HStack(spacing: DS.Spacing.sm) {
                    if !replyPhone.isEmpty {
                        replyButton(
                            title: L10n.t("واتساب", "WhatsApp"),
                            icon: "message.fill",
                            // أخضر واتساب الثابت (#25D366) كان باهتاً جداً على خلفيته في الوضع الفاتح
                            // (~1.8:1) — لون أخضر من ألوان التطبيق يُقرأ في الوضعين
                            color: DS.Color.secondary
                        ) { openURL("https://wa.me/\(sanitize(replyPhone))") }
                        replyButton(
                            title: L10n.t("اتصال", "Call"),
                            icon: "phone.fill",
                            color: DS.Color.success
                        ) { openURL("tel:\(sanitize(replyPhone))") }
                    }
                    if isEmail {
                        replyButton(
                            title: L10n.t("بريد", "Email"),
                            icon: "envelope.fill",
                            color: DS.Color.info
                        ) { showEmailComposer = true }
                    }
                }
            }
        }
    }

    private func preferredContactRow(_ preferred: String, isEmail: Bool) -> some View {
        Button {
            UIPasteboard.general.string = preferred
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: isEmail ? "envelope.fill" : "phone.fill", tint: DS.Color.info)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("وسيلة التواصل", "Preferred contact"))
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(preferred)
                        .dsFieldFont(.fieldValue)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .dsGlyph(DS.Glyph.mdCompact, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        // رمز النسخ للعين فقط — القارئ الصوتي يعرف أن الضغط ينسخ
        .accessibilityHint(L10n.t("ينسخ وسيلة التواصل", "Copies the contact"))
    }

    /// الزرّ الواحد (٤٤) بلون الوسيلة صلباً (واتساب، اتصال، بريد)
    private func replyButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        DSButton(title, icon: icon, tint: color, action: action)
    }

    private func sanitize(_ phone: String) -> String {
        phone.filter { $0.isNumber || $0 == "+" }
    }

    private func openURL(_ str: String) {
        guard let url = URL(string: str) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func markHandled() async {
        isMarking = true
        adminRequestVM.markContactMessageRead(message.id)
        await adminRequestVM.markContactMessageHandled(message)
        isMarking = false
        onDismiss()
    }
}

// MARK: - Helpers

enum ContactParser {
    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// تحويل ISO string لـ Date (يدعم بكسر ثواني أو بدونها).
    static func date(_ str: String?) -> Date? {
        guard let s = str, !s.isEmpty else { return nil }
        return isoFull.date(from: s) ?? isoBasic.date(from: s)
    }

    /// التصنيف: من new_value مباشرة، fallback لتحليل details.
    static func category(of msg: AdminRequest) -> String {
        if let nv = msg.newValue?.trimmingCharacters(in: .whitespacesAndNewlines), !nv.isEmpty {
            return nv
        }
        guard let details = msg.details else { return "—" }
        for line in details.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("التصنيف:") {
                return String(trimmed.dropFirst("التصنيف:".count)).trimmingCharacters(in: .whitespaces)
            }
            if trimmed.lowercased().hasPrefix("category:") {
                return String(trimmed.dropFirst("category:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return "—"
    }

    /// وسيلة التواصل التي كتبها العضو للرد (إيميل أو رقم) — إن وُجدت.
    static func preferredContact(from msg: AdminRequest) -> String? {
        guard let details = msg.details else { return nil }
        for line in details.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("وسيلة التواصل:") {
                let v = String(t.dropFirst("وسيلة التواصل:".count)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            if t.lowercased().hasPrefix("preferred contact:") {
                let v = String(t.dropFirst("preferred contact:".count)).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    /// نص الرسالة: من سطر "الرسالة:" أو "Message:" — fallback للنص الكامل.
    static func message(from msg: AdminRequest) -> String {
        guard let details = msg.details else { return "" }
        let lines = details.components(separatedBy: .newlines)
        var capturing = false
        var collected: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("الرسالة:") {
                capturing = true
                let rest = String(trimmed.dropFirst("الرسالة:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { collected.append(rest) }
                continue
            }
            if trimmed.lowercased().hasPrefix("message:") {
                capturing = true
                let rest = String(trimmed.dropFirst("message:".count)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { collected.append(rest) }
                continue
            }
            if trimmed.hasPrefix("التصنيف:") || trimmed.lowercased().hasPrefix("category:") {
                continue
            }
            if trimmed.hasPrefix("وسيلة التواصل:") || trimmed.lowercased().hasPrefix("preferred contact:") {
                capturing = false
                continue
            }
            if capturing && !trimmed.isEmpty { collected.append(trimmed) }
        }
        if collected.isEmpty {
            return details
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("التصنيف:") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
        }
        return collected.joined(separator: "\n")
    }
}

/// عرض موحّد للتصنيف (لون/أيقونة/ترجمة) بناءً على نص خام من قاعدة البيانات.
struct ContactCategoryInfo {
    let title: String
    let icon: String
    let color: Color

    static func from(raw: String) -> ContactCategoryInfo {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "شكوى", "complaint", "Complaint":
            return .init(title: L10n.t("شكوى", "Complaint"), icon: "exclamationmark.bubble.fill", color: DS.Color.sadu)
        case "اقتراح", "suggestion", "Suggestion":
            return .init(title: L10n.t("اقتراح", "Suggestion"), icon: "lightbulb.fill", color: DS.Color.palm)
        case "استفسار", "inquiry", "Inquiry":
            return .init(title: L10n.t("استفسار", "Inquiry"), icon: "questionmark.bubble.fill", color: AppSection.admin.ink)
        case "أخرى", "other", "Other":
            return .init(title: L10n.t("أخرى", "Other"), icon: "ellipsis.message.fill", color: DS.Color.accent)
        default:
            return .init(title: trimmed.isEmpty ? "—" : trimmed, icon: "envelope.fill", color: DS.Color.textSecondary)
        }
    }
}


// MARK: - شيت الرد الرسمي (يُرسل من بريد العائلة عبر الخادم)

/// «الرد بالبريد» — مربّع كتابة بنفس التصميم الموحّد (طلب المالك): المستلم ثم نص الرد،
/// و«إرسال الرد» / «إغلاق» أسفل المربّع
private struct OfficialReplySheet: View {
    let to: String
    let memberName: String
    let category: String
    let originalMessage: String

    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var didSend = false

    private var canSend: Bool {
        !(isSending || didSend || replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("الرد بالبريد", "Email reply"),
            subtitle: memberName.isEmpty ? L10n.t("العضو", "Member") : memberName,
            icon: "envelope.badge.fill",
            tint: DS.Color.actionNavy,
            actionTitle: didSend ? L10n.t("تم الإرسال", "Sent") : L10n.t("إرسال الرد", "Send reply"),
            actionIcon: didSend ? "checkmark.circle.fill" : "paperplane.fill",
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: canSend,
            isBusy: isSending,
            // ردّ مكتوب لم يُرسل → «إغلاق» يسأل قبل التجاهل (توصية أبل)؛ بعد الإرسال لا سؤال
            hasUnsavedChanges: !didSend && !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onSubmit: { Task { await send() } },
            onCancel: { dismiss() }
        ) {
            recipientSection
            replySection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: المستلم

    private var recipientSection: some View {
        DSComposerSection(title: L10n.t("المستلم", "Recipient"),
                          icon: "person.fill",
                          tint: DS.Color.info,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "envelope.badge.fill", tint: DS.Color.info)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(memberName.isEmpty ? L10n.t("العضو", "Member") : memberName)
                        .dsFont(.headlineCompact)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    Text(to)
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: نص الرد

    private var replySection: some View {
        DSComposerSection(title: L10n.t("الرد على العضو", "Reply to member"),
                          icon: "arrowshape.turn.up.left.fill",
                          tint: AppSection.admin.ink,
                          index: 1) {
            ReplyComposerField(label: L10n.t("نص الرد", "Reply"),
                               placeholder: L10n.t("اكتب ردّك هنا…", "Write your reply…"),
                               text: $replyText)

            if let errorText {
                DSNoteCard(errorText, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    @MainActor
    private func send() async {
        errorText = nil
        isSending = true
        defer { isSending = false }
        do {
            struct Payload: Encodable {
                let to: String, reply: String, member_name: String
                let original_message: String, category: String
            }
            _ = try await SupabaseConfig.client.functions.invoke(
                "admin-reply-email",
                options: .init(body: Payload(
                    to: to,
                    reply: replyText.trimmingCharacters(in: .whitespacesAndNewlines),
                    member_name: memberName,
                    original_message: originalMessage,
                    category: category
                ))
            )
            didSend = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            Log.error("[AdminReply] فشل إرسال الرد: \(error.localizedDescription)")
            errorText = L10n.t("تعذّر إرسال الرد. حاول مرة أخرى.", "Could not send the reply. Try again.")
        }
    }
}

/// حقل نص الرد — بنفس شكل `DSComposerField` لكنه أطول (يبدأ بستة أسطر)،
/// فالرد البريدي يحتاج مساحة كتابة مثل محرّر النص السابق
private struct ReplyComposerField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var tint: Color = AppSection.admin.ink
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "square.and.pencil")
                .dsGlyph(DS.Glyph.mdCompact, weight: .semibold)
                .foregroundColor(focused ? DS.Color.textOnPrimary : tint)
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                    .fill(focused ? tint : tint.opacity(DS.Opacity.tintFill)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(label)
                    .dsFieldFont(.label)
                    .foregroundColor(focused ? tint : DS.Color.fieldLabel)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(6...12)
                    .dsFieldFont(.fieldValue)
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($focused)
            }
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.sm)
        .dsFocusFieldBox(focused: focused, tint: tint)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }
}


/// رأس صفحة «رسائل التواصل» — يُحذف داخل «الوارد» (رأسه فوقها)
private struct InboxHeader: ViewModifier {
    let embedded: Bool
    let hasMessages: Bool
    let isSelectMode: Bool
    let toggleSelect: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if embedded {
            content
        } else {
            content
                .dsSubPageHeader(L10n.t("رسائل التواصل", "Contact Messages"),
                                 subtitle: L10n.t("رسائل الأعضاء من «تواصل مع الإدارة» — اضغط أي رسالة للرد عليها",
                                                  "Members' messages from “Contact Admin” — tap one to reply")) {
                    if hasMessages {
                        DSHeaderButton(symbol: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle",
                                       label: isSelectMode ? L10n.t("تم", "Done") : L10n.t("تحديد", "Select"),
                                       action: toggleSelect)
                    }
                }
        }
    }
}
