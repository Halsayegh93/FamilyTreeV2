import SwiftUI
import Supabase

/// قائمة رسائل التواصل من الأعضاء — نموذج بسيط (لا دردشة).
/// كل صف = رسالة واحدة. الضغط يفتح تفاصيلها مع خيارات الرد بالاتصال/واتساب.
///
/// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧): بطاقة رأس بلون بلاطة «الرسائل» في لوحة
/// الإدارة وأرقامها الحيّة ← بحث + فلترا الحالة بعددهما ← صفوف `.dsRowBox()` (صورة المرسل · الاسم
/// والوقت · مقتطف الرسالة · التصنيف والحالة). السحب («حذف» / «تم التعامل»)، التحديد المتعدد والحذف
/// وتأكيداتهما، السحب للتحديث، ومربّع التفاصيل كما كانت تماماً.
struct AdminInboxView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel

    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var selectedMessage: AdminRequest? = nil
    @State private var filter: InboxFilter = .pending
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
            case .pending: return L10n.t("لم يتم التعامل", "Pending")
            case .handled: return L10n.t("تم التعامل", "Handled")
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

    private var filteredMessages: [AdminRequest] {
        let all = adminRequestVM.contactMessages
        let byStatus: [AdminRequest]
        switch filter {
        case .pending: byStatus = all.filter { $0.status == ApprovalStatus.pending.rawValue }
        case .handled: byStatus = all.filter { $0.status == ApprovalStatus.approved.rawValue }
        }
        let sorted = byStatus.sorted { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return sorted }
        return sorted.filter { msg in
            let name = msg.member?.fullName.lowercased() ?? ""
            let preview = ContactParser.message(from: msg).lowercased()
            return name.contains(q) || preview.contains(q)
        }
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

    var body: some View {
        let messages = filteredMessages
        let counts = statusCounts

        return ZStack {
            DS.Color.background.ignoresSafeArea()

            // بطاقة الرأس ← البحث والفلاتر ← الرسائل: تتمرّر معاً (والسحب للتحديث يعمل حتى والقائمة فارغة)
            ScrollView(showsIndicators: false) {
                pageContent(messages: messages, counts: counts)
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
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !messages.isEmpty {
                    Button {
                        withAnimation(DS.Anim.quick) {
                            isSelectMode.toggle()
                            if !isSelectMode { selectedIDs.removeAll() }
                        }
                    } label: {
                        Image(systemName: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundColor(DS.Color.primary)
                    }
                    .accessibilityLabel(isSelectMode ? L10n.t("تم", "Done") : L10n.t("تحديد", "Select"))
                }
            }
        }
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
        .navigationTitle(L10n.t("رسائل التواصل", "Contact Messages"))
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - هيكل الصفحة

    private func pageContent(messages: [AdminRequest], counts: [InboxFilter: Int]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            heroSection(counts: counts)

            if isInitialLoading {
                SysStateCard(icon: "bubble.left.and.bubble.right.fill",
                             title: L10n.t("جارٍ تحميل الرسائل…", "Loading messages…"),
                             tint: pageTint,
                             isLoading: true)
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(1)
            } else if loadFailed {
                SysStateCard(icon: "wifi.exclamationmark",
                             title: L10n.t("تعذّر تحميل الرسائل", "Couldn't load messages"),
                             hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                             tint: DS.Color.error,
                             actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                             action: { Task { await retryLoad() } })
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(1)
            } else {
                DSSearchField(text: $searchText,
                              placeholder: L10n.t("ابحث…", "Search…"),
                              tint: pageTint)
                    .dsStaggerIn(1)

                filterChips(counts)
                    .dsStaggerIn(1)

                if messages.isEmpty {
                    emptyState(counts: counts)
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(2)
                } else {
                    if adminRequestVM.unreadContactMessagesCount > 0 {
                        markAllReadBar
                            .dsStaggerIn(2)
                    }

                    // عنوان الحالة المختارة + عدد ما يظهر منها
                    SysSectionTitle(title: filter.title,
                                    icon: filter.icon,
                                    tint: filter.color,
                                    trailing: L10n.t("\(messages.count) رسالة", "\(messages.count) messages"))
                        .dsStaggerIn(2)

                    AdaptiveLazyStack(spacing: DS.Spacing.sm, landscapeMinimum: 340) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, msg in
                            messageCell(msg)
                                // نمط الأخبار والديوانيات: أول ٧ تصعد تباعاً، وما يُبنى بالتمرير يظهر مباشرة
                                .dsCardCascade(index, appeared: appeared)
                        }
                    }
                    .onAppear(perform: startRowsCascade)
                }
            }
        }
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
        DSPageHero(
            title: L10n.t("رسائل التواصل", "Contact Messages"),
            subtitle: L10n.t("رسائل الأعضاء من «تواصل مع الإدارة» — اضغط أي رسالة للرد عليها",
                             "Members' messages from “Contact Admin” — tap one to reply"),
            icon: "bubble.left.and.bubble.right.fill",
            tint: pageTint,
            stats: heroStats(counts: counts)
        )
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
            DSSwipeAction(icon: "trash.fill", title: L10n.t("حذف", "Delete"), color: DS.Color.error) {
                messageToDelete = msg
            }
        ]
        if msg.status == ApprovalStatus.pending.rawValue {
            actions.append(DSSwipeAction(icon: "checkmark.circle.fill", title: L10n.t("تم التعامل", "Handled"),
                                         color: DS.Color.success) {
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
                .dsFieldFont(13.5, weight: .bold)
                .foregroundColor(DS.Color.fieldValue)
                .monospacedDigit()
            Spacer()
            Button {
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 6) {
                    if isDeleting {
                        ProgressView().tint(DSActionFill.label()).scaleEffect(0.85)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    Text(L10n.t("حذف", "Delete"))
                        .font(DS.Font.plex(14, weight: .bold))
                }
                .foregroundColor(DSActionFill.label())
                .padding(.horizontal, DS.Spacing.xl)
                .frame(minHeight: 44)
                .background(Capsule().fill(DS.Color.error))
                .contentShape(Capsule())
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(selectedIDs.isEmpty || isDeleting)
            .opacity(selectedIDs.isEmpty ? 0.5 : 1)
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
            SysStateCard(icon: "magnifyingglass",
                         title: L10n.t("لا توجد نتائج", "No results"),
                         hint: L10n.t("جرّب كلمة أخرى", "Try another word"),
                         tint: DS.Color.textTertiary)
        } else {
            let other: InboxFilter = filter == .pending ? .handled : .pending
            let otherCount = counts[other] ?? 0
            let showOther: (() -> Void)? = otherCount > 0 ? { showFilter(other) } : nil
            SysStateCard(icon: filter == .pending ? "checkmark.circle.fill" : "tray",
                         title: L10n.t("ما فيه رسائل", "No messages"),
                         hint: filter == .pending
                            ? L10n.t("كل الرسائل تم التعامل معها", "All messages handled")
                            : L10n.t("لا توجد رسائل متعامل معها بعد", "No handled messages yet"),
                         tint: filter == .pending ? DS.Color.success : DS.Color.textTertiary,
                         actionTitle: otherCount > 0
                            ? L10n.t("عرض «\(other.title)» (\(otherCount))", "Show \(other.title) (\(otherCount))")
                            : nil,
                         actionIcon: other.icon,
                         action: showOther)
        }
    }

    private func showFilter(_ f: InboxFilter) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { filter = f }
    }

    // MARK: - Row

    /// الخلية: دائرة التحديد (في وضع التحديد) + الصف.
    /// ضغطة فعلية فقط تفتح التفاصيل — السحب لا يفتحها (طلب المالك).
    /// (زر Button كان يعدّ رفع الإصبع بعد السحب ضغطة)
    private func messageCell(_ msg: AdminRequest) -> some View {
        let picked = selectedIDs.contains(msg.id)
        let isUnread = !adminRequestVM.readContactMessageIds.contains(msg.id)
        let actions = isSelectMode ? [] : swipeActions(for: msg)

        return HStack(spacing: DS.Spacing.sm) {
            if isSelectMode {
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(DS.Font.scaled(20, weight: .semibold))
                    .foregroundColor(picked ? DS.Color.primary : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            messageRow(msg, isUnread: isUnread, picked: picked)
        }
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

    /// صف بإطار صفوف المربّعات: صورة المرسل (ونقطة «جديد» على ركنها) + الاسم (Plex 13.5 عريض)
    /// وشارة الوقت + مقتطف الرسالة (Plex 12) + شارتا التصنيف و«بانتظار الرد»
    private func messageRow(_ msg: AdminRequest, isUnread: Bool, picked: Bool) -> some View {
        let info = ContactCategoryInfo.from(raw: ContactParser.category(of: msg))
        let preview = ContactParser.message(from: msg)
        let date = ContactParser.date(msg.createdAt)
        let isPending = msg.status == ApprovalStatus.pending.rawValue

        return HStack(alignment: .top, spacing: DS.Spacing.sm) {
            avatar(for: msg.member, isUnread: isUnread)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: DS.Spacing.xs) {
                    // الاسم بخط IBM Plex وعلى سطرين (طلب المالك)
                    Text(msg.member?.displayFullName ?? L10n.t("عضو", "Member"))
                        .dsFieldFont(13.5, weight: isUnread ? .bold : .semibold)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Spacing.xs)
                    if let date {
                        // الوقت — أزرق للرسالة الجديدة، رمادي لما قُرئ
                        SysStatusChip(text: relativeShort(date),
                                      tint: isUnread ? DS.Color.primary : DS.Color.textTertiary)
                            .fixedSize()
                    }
                }

                if !preview.isEmpty {
                    Text(preview)
                        .dsFieldFont(12, weight: isUnread ? .medium : .regular)
                        .foregroundColor(isUnread ? DS.Color.fieldLabel : DS.Color.fieldValue)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 6) {
                    SysStatusChip(text: info.title, icon: info.icon, tint: info.color)
                    if isPending {
                        SysStatusChip(text: L10n.t("بانتظار الرد", "Awaiting reply"),
                                      icon: "clock.fill",
                                      tint: DS.Color.warning)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .overlay {
            // المحدّدة بإطار أوضح، والجديدة بإطار أزرق خفيف
            if isSelectMode && picked {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(0.55), lineWidth: 1.5)
            } else if isUnread {
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(0.30), lineWidth: 1.2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: - Mark all read bar

    /// «N رسالة جديدة» + «تحديد الكل كمقروء» — صف بإطار صفوف المربّعات
    private var markAllReadBar: some View {
        let unread = adminRequestVM.unreadContactMessagesCount
        return HStack(spacing: DS.Spacing.sm) {
            DSFieldIcon(name: "envelope.badge.fill", tint: DS.Color.primary)
                .accessibilityHidden(true)
            Text(L10n.t("\(unread) رسالة جديدة", "\(unread) new messages"))
                .dsFieldFont(13, weight: .bold)
                .foregroundColor(DS.Color.fieldLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Button {
                withAnimation(DS.Anim.quick) {
                    adminRequestVM.markAllContactMessagesRead()
                }
            } label: {
                actionCapsule(icon: "envelope.open.fill",
                              title: L10n.t("تحديد الكل كمقروء", "Mark all read"),
                              tint: DS.Color.primary)
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .dsRowBox()
    }

    /// كبسولة إجراء صغيرة — مساحة ضغط ٤٤ نقطة والشكل كما هو
    private func actionCapsule(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .accessibilityHidden(true)
            Text(title)
                .font(DS.Font.plex(12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundColor(tint)
        .padding(.horizontal, DS.Spacing.md)
        .frame(height: 30)
        .background(tint.opacity(0.10), in: Capsule())
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .padding(.vertical, -7)
    }

    /// صورة المرسل — ونقطة «جديد» صغيرة على ركنها للرسالة غير المقروءة
    private func avatar(for member: FamilyMember?, isUnread: Bool) -> some View {
        DSMemberAvatar(
            name: member?.firstName ?? "?",
            avatarUrl: member?.avatarUrl,
            size: 36,
            roleColor: member?.roleColor ?? DS.Color.primary
        )
        .overlay(alignment: .topTrailing) {
            if isUnread {
                Circle()
                    .fill(DS.Color.primary)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(DS.Color.background, lineWidth: 1.5))
            }
        }
        .accessibilityHidden(true)
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
            actionTitle: isMarking ? L10n.t("جارٍ…", "Working…") : L10n.t("تم التعامل", "Mark as Handled"),
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
                memberName: message.member?.fullName ?? "",
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
                                 tint: DS.Color.primary,
                                 index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                DSMemberAvatar(
                    name: message.member?.firstName ?? "?",
                    avatarUrl: message.member?.avatarUrl,
                    size: 44,
                    roleColor: message.member?.roleColor ?? DS.Color.primary
                )
                .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.member?.displayFullName ?? L10n.t("عضو", "Member"))
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !phone.isEmpty {
                        Text(phone)
                            .dsFieldFont(12)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 2) {
                    Image(systemName: info.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(info.color)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(info.color.opacity(0.14)))
                        .accessibilityHidden(true)   // التصنيف يُقرأ من النص تحته
                    Text(info.title)
                        .font(DS.Font.plex(10.5, weight: .semibold))
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
                .font(DS.Font.plex(15))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsRowBox()

            if !isPending {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "checkmark.seal.fill", tint: DS.Color.success)
                        .accessibilityHidden(true)
                    Text(L10n.t("تم التعامل مع هذه الرسالة", "This message was handled"))
                        .font(DS.Font.plex(13.5, weight: .semibold))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("وسيلة التواصل", "Preferred contact"))
                        .dsFieldFont(12, weight: .heavy)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(preferred)
                        .dsFieldFont(14.5)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
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

    private func replyButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Font.plex(13.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(color.opacity(0.12)))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(color.opacity(0.25), lineWidth: 1)
            )
            // مساحة ضغط ٤٤ (توصية أبل) — الشكل والارتفاع في الصف كما هما
            .frame(height: 44)
            .contentShape(Rectangle())
            .padding(.vertical, -1)
        }
        .buttonStyle(DSScaleButtonStyle())
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
            return .init(title: L10n.t("شكوى", "Complaint"), icon: "exclamationmark.bubble.fill", color: DS.Color.error)
        case "اقتراح", "suggestion", "Suggestion":
            return .init(title: L10n.t("اقتراح", "Suggestion"), icon: "lightbulb.fill", color: DS.Color.success)
        case "استفسار", "inquiry", "Inquiry":
            return .init(title: L10n.t("استفسار", "Inquiry"), icon: "questionmark.bubble.fill", color: DS.Color.primary)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(memberName.isEmpty ? L10n.t("العضو", "Member") : memberName)
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    Text(to)
                        .dsFieldFont(12)
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
                          tint: DS.Color.primary,
                          index: 1) {
            ReplyComposerField(label: L10n.t("نص الرد", "Reply"),
                               placeholder: L10n.t("اكتب ردّك هنا…", "Write your reply…"),
                               text: $replyText)

            if let errorText {
                Text(errorText)
                    .font(DS.Font.plex(12, weight: .semibold))
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
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
    var tint: Color = DS.Color.primary
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(focused ? .white : tint)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(focused ? tint : tint.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .dsFieldFont(12, weight: .heavy)
                    .foregroundColor(focused ? tint : DS.Color.fieldLabel)
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(6...12)
                    .dsFieldFont(14.5)
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($focused)
            }
        }
        .padding(.horizontal, DS.Spacing.sm + 2)
        .padding(.vertical, DS.Spacing.sm)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(focused ? tint.opacity(0.65) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: focused ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeInOut(duration: 0.2), value: focused)
    }
}
