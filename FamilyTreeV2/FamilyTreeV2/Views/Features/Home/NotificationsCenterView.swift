import SwiftUI
import Supabase

// MARK: - Notification Kind Style (data-driven icon/color/label mapping)

private struct NotificationKindStyle {
    let icon: String
    let gradient: LinearGradient
    let color: Color
    let labelAr: String
    let labelEn: String

    var label: String { L10n.t(labelAr, labelEn) }

    private static let styles: [String: NotificationKindStyle] = [
        // — كل الأيقونات تستخدم ألوان Vivid Spectrum (الأزرق/الأخضر/البنفسجي) —
        "approval":          .init(icon: "checkmark.circle.fill",                    gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "عضوية",           labelEn: "Membership"),
        "join_approved":     .init(icon: "checkmark.circle.fill",                    gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "عضوية",           labelEn: "Membership"),
        "join_request":      .init(icon: "link.circle.fill",                         gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "طلب انضمام",      labelEn: "Join Request"),
        "news":              .init(icon: "newspaper.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "أخبار",           labelEn: "News"),
        "news_add":          .init(icon: "newspaper.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "أخبار",           labelEn: "News"),
        "admin":             .init(icon: "megaphone.fill",                           gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "إعلان من الإدارة", labelEn: "Admin Announcement"),
        "admin_broadcast":   .init(icon: "megaphone.fill",                           gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "إعلان من الإدارة", labelEn: "Admin Announcement"),
        "admin_request":     .init(icon: "shield.fill",                              gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "إدارة",           labelEn: "Admin"),
        "deceased_report":   .init(icon: "heart.fill",                               gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "وفاة",            labelEn: "Deceased"),
        "child_add":         .init(icon: "person.badge.plus",                        gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "إضافة ابن",       labelEn: "Child Add"),
        "admin_edit_child_add":   .init(icon: "person.badge.plus",                   gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "إضافة ابن",       labelEn: "Child Add"),
        "admin_edit_child_remove":.init(icon: "person.badge.minus",                  gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "حذف ابن",         labelEn: "Child Removed"),
        "member_delete":     .init(icon: "trash.fill",                               gradient: DS.Color.gradientAccent,  color: DS.Color.error,       labelAr: "حذف عضو",         labelEn: "Member Removed"),
        "member_add":        .init(icon: "person.fill.badge.plus",                   gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "إضافة عضو",       labelEn: "Member Added"),
        "admin_edit":        .init(icon: "pencil.circle.fill",                       gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل بيانات",    labelEn: "Edit"),
        "admin_edit_name":   .init(icon: "pencil",                                   gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل اسم",       labelEn: "Name Edit"),
        "admin_edit_dates":  .init(icon: "calendar",                                 gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل تواريخ",    labelEn: "Dates Edit"),
        "admin_edit_phone":  .init(icon: "phone.arrow.right",                        gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل رقم",       labelEn: "Phone Edit"),
        "admin_edit_phone_remove": .init(icon: "phone.down.fill",                    gradient: DS.Color.gradientAccent,  color: DS.Color.error,       labelAr: "حذف رقم",         labelEn: "Phone Removed"),
        "admin_edit_role":   .init(icon: "shield.lefthalf.filled",                   gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل صلاحية",    labelEn: "Role Edit"),
        "admin_edit_father": .init(icon: "person.2.fill",                            gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل أب",        labelEn: "Father Edit"),
        "admin_edit_avatar": .init(icon: "camera.circle.fill",                       gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "تعديل صورة",      labelEn: "Photo Edit"),
        "admin_edit_avatar_remove": .init(icon: "camera.metering.unknown",           gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "حذف صورة",        labelEn: "Photo Removed"),
        "admin_child_add":   .init(icon: "person.badge.plus",                        gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "إضافة ابن",       labelEn: "Child Add"),
        "phone_change":      .init(icon: "phone.arrow.right",                        gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "تغيير رقم",       labelEn: "Phone Change"),
        "news_report":       .init(icon: "exclamationmark.triangle.fill",            gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "بلاغ خبر",        labelEn: "News Report"),
        "news_deleted":      .init(icon: "trash.fill",                               gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "حذف منشور",       labelEn: "Post Deleted"),
        "contact_message":   .init(icon: "envelope.fill",                            gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "تواصل",           labelEn: "Contact"),
        "contact_reply":     .init(icon: "envelope.open.fill",                       gradient: DS.Color.gradientPrimary, color: DS.Color.success,     labelAr: "رد من الإدارة",   labelEn: "Admin Reply"),
        "link_request":      .init(icon: "link.circle.fill",                         gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "طلب ربط",         labelEn: "Link Request"),
        "gallery_add":       .init(icon: "photo.fill",                               gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "معرض صور",        labelEn: "Gallery"),
        "news_comment":      .init(icon: "bubble.left.fill",                         gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "تعليق",           labelEn: "Comment"),
        "news_like":         .init(icon: "heart.fill",                               gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "إعجاب",           labelEn: "Like"),
        "news_published":    .init(icon: "megaphone.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "خبر جديد",        labelEn: "New Post"),
        "profile_update":    .init(icon: "person.crop.circle.badge.checkmark",       gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "تحديث بيانات",    labelEn: "Profile Update"),
        "account_activated": .init(icon: "checkmark.seal.fill",                      gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "تفعيل حساب",      labelEn: "Activated"),
        "role_change":       .init(icon: "shield.lefthalf.filled",                   gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تغيير الصلاحية",  labelEn: "Role Change"),
        "weekly_digest":     .init(icon: "list.clipboard.fill",                      gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "ملخص أسبوعي",     labelEn: "Weekly Digest"),
        "tree_edit":         .init(icon: "pencil.circle.fill",                       gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "تعديل شجرة",      labelEn: "Tree Edit"),
        "story_pending":     .init(icon: "circle.dashed",                            gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "قصة معلقة",        labelEn: "Pending Story"),
        "story_approved":    .init(icon: "checkmark.circle.fill",                    gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "قصة معتمدة",      labelEn: "Story Approved"),
        "story_rejected":    .init(icon: "xmark.circle.fill",                        gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "قصة مرفوضة",      labelEn: "Story Rejected"),
        "photo_suggestion":  .init(icon: "camera.badge.ellipsis",                    gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "اقتراح صورة",     labelEn: "Photo Suggestion"),
        "gallery_pending":   .init(icon: "photo.fill",                               gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "صورة معرض",        labelEn: "Gallery Photo"),
        "gallery_approved":  .init(icon: "photo.fill",                               gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "صورة معتمدة",      labelEn: "Photo Approved"),
        "gallery_rejected":  .init(icon: "photo.fill",                               gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "صورة مرفوضة",      labelEn: "Photo Rejected"),
        "diwaniya_pending":  .init(icon: "tent.fill",                                gradient: DS.Color.gradientPrimary, color: DS.Color.primary,     labelAr: "ديوانية جديدة",   labelEn: "New Diwaniya"),
        "diwaniya_approved": .init(icon: "tent.fill",                                gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "ديوانية معتمدة",   labelEn: "Diwaniya Approved"),
        "diwaniya_rejected": .init(icon: "tent.fill",                                gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "ديوانية مرفوضة",   labelEn: "Diwaniya Rejected"),
        "project_pending":   .init(icon: "briefcase.fill",                           gradient: DS.Color.gradientAccent,  color: DS.Color.accent,      labelAr: "مشروع جديد",       labelEn: "New Project"),
        "project_approved":  .init(icon: "briefcase.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.secondary,   labelAr: "مشروع معتمد",      labelEn: "Project Approved"),
        "project_rejected":  .init(icon: "briefcase.fill",                           gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "مشروع مرفوض",      labelEn: "Project Rejected"),
    ]

    private static let fallback = NotificationKindStyle(
        icon: "bell.fill", gradient: DS.Color.gradientPrimary, color: DS.Color.primary,
        labelAr: "إشعار", labelEn: "Notification"
    )

    static func style(for kind: String) -> NotificationKindStyle {
        styles[kind] ?? fallback
    }
}

// MARK: - Layout Constants

/// Preference key لقياس ارتفاع محتوى شيت تفاصيل الإشعار
private struct DetailSheetHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum NotifLayout {
    /// Detail info row icon column width (also used by detailDivider leading inset)
    static let infoIconWidth: CGFloat = 28
    /// Notification row icon circle size
    static let rowIconSize: CGFloat = 44
    /// Selection badge min dimension
    static let badgeSize: CGFloat = 22
}

struct NotificationsCenterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — نضغط المسافات العمودية حتى لا يُقتص المحتوى
    private var isLandscape: Bool { vSizeClass == .compact }

    @AppStorage("notif_comments") private var notifComments: Bool = true
    @AppStorage("notif_likes") private var notifLikes: Bool = true
    @AppStorage("notif_profile_updates") private var notifProfileUpdates: Bool = true

    @State private var appeared = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var selectedNotification: AppNotification? = nil
    /// العضو المختار لفتح تفاصيله من داخل الإشعار (مثل الشجرة).
    @State private var selectedMember: FamilyMember? = nil
    /// detent المختار حالياً — يُحدَّث ديناميكياً ليتطابق مع ارتفاع المحتوى
    @State private var detailSheetDetent: PresentationDetent = .height(450)
    /// آخر ارتفاع تم قياسه للمحتوى
    @State private var measuredDetailHeight: CGFloat = 450
    /// طلب admin_requests المرتبط بالإشعار الحالي — يُحمَّل عند فتح الشيت (للمرحلة ٣)
    @State private var loadedAdminRequest: AdminRequest? = nil
    /// نتائج مطابقة اسم/أب لطلبات الانضمام
    @State private var joinMatchCandidates: [FamilyMember] = []
    /// هل كرت التطابقات موسّع — افتراضياً مغلق
    @State private var joinMatchesExpanded: Bool = false
    /// true بعد انتهاء loadJoinMatchCandidates — يميّز بين "جاري التحميل" و"لا توجد مطابقات"
    @State private var joinMatchesLoaded: Bool = false
    /// confirmation dialog لخيارات الموافقة على طلب الانضمام (ربط أو إنشاء جديد)
    @State private var joinApproveDialog: AppNotification? = nil
    /// alert تأكيد قبل ربط طلب انضمام بعضو موجود (من قائمة المطابقات المحتملة)
    @State private var linkConfirmTarget: LinkConfirmation? = nil

    /// بيانات ربط مؤقتة — تُحمل في alert التأكيد
    private struct LinkConfirmation: Identifiable {
        let id = UUID()
        let notificationId: UUID
        let requesterId: UUID
        let candidate: FamilyMember
    }
    @State private var selectedTab: NotifTab = .notifications
    @Namespace private var tabIndicator

    enum NotifTab: Hashable {
        case notifications // إشعاراتي + موافقات
        case activity      // المستجدات — للمدراء فقط
    }

    // MARK: - Date Formatters

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func fullDateTime(_ date: Date) -> String {
        Self.fullDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.fullDateFormatter.string(from: date)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // صفحتين — الإشعارات + المستجدات
                if authVM.isAdmin {
                    let visible = visibleNotifications
                    let notifUnread = visible.filter { belongsToNotificationsTab($0) && !$0.read }.count
                    let activityUnread = visible.filter { belongsToActivityTab($0) && !$0.read }.count

                    segmentedTabBar(notifCount: notifUnread, activityCount: activityUnread)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.bottom, DS.Spacing.xs)
                }

                // شريط الأدوات الموحد
                actionBar

                if notificationVM.isLoading && filteredNotifications.isEmpty {
                    Spacer()
                    ProgressView(L10n.t("جاري التحميل...", "Loading..."))
                        .tint(DS.Color.primary)
                    Spacer()
                } else if filteredNotifications.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    notificationsList
                }
            }
        }
        .navigationTitle(L10n.t("الإشعارات", "Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isSelecting)
        .task {
            await notificationVM.fetchNotifications()
            // Deep-link من push خارجي لطلب انضمام: افتح شيت التفاصيل مباشرة
            if let rid = notificationVM.pendingJoinDeepLinkRequestId {
                if let target = notificationVM.notifications.first(where: { $0.requestId == rid }) {
                    selectedNotification = target
                }
                notificationVM.pendingJoinDeepLinkRequestId = nil
            }
        }
        .onChange(of: notificationVM.pendingJoinDeepLinkRequestId) { newValue in
            // إذا وصل deep-link بينما الشاشة مفتوحة، استهلكه فوراً
            guard let rid = newValue else { return }
            if let target = notificationVM.notifications.first(where: { $0.requestId == rid }) {
                selectedNotification = target
            }
            notificationVM.pendingJoinDeepLinkRequestId = nil
        }
        .onAppear {
            withAnimation(DS.Anim.smooth.delay(0.15)) {
                appeared = true
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .sheet(item: $selectedNotification) { notification in
            notificationDetailSheet(notification)
        }
        .alert(
            {
                if case .failure = adminRequestVM.mergeResult {
                    return L10n.t("لم يتم الربط", "Link Failed")
                }
                return L10n.t("تم الربط بنجاح", "Linked Successfully")
            }(),
            isPresented: Binding(
                get: { adminRequestVM.mergeResult != nil },
                set: { if !$0 { adminRequestVM.mergeResult = nil } }
            ),
            presenting: adminRequestVM.mergeResult
        ) { _ in
            Button(L10n.t("حسناً", "OK"), role: .cancel) {
                adminRequestVM.mergeResult = nil
            }
        } message: { result in
            switch result {
            case .success(let msg), .failure(let msg):
                Text(msg)
            }
        }
    }

    // MARK: - Action Bar (Unified)

    private var actionBar: some View {
        let unreadCount = filteredNotifications.filter { !$0.read }.count

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {

                if isSelecting {
                    // ── وضع التحديد ──

                    // إلغاء
                    pillButton(
                        icon: "xmark",
                        label: L10n.t("إلغاء", "Cancel"),
                        fg: DS.Color.error,
                        bg: DS.Color.error.opacity(0.10)
                    ) {
                        withAnimation(DS.Anim.snappy) {
                            isSelecting = false
                            selectedIds.removeAll()
                        }
                    }

                    // تحديد الكل / إلغاء الكل
                    let allIds = Set(filteredNotifications.map(\.id))
                    let allSelected = !allIds.isEmpty && selectedIds == allIds
                    pillButton(
                        icon: allSelected ? "checkmark.square.fill" : "square.dashed",
                        label: allSelected ? L10n.t("إلغاء الكل", "Deselect") : L10n.t("الكل", "All"),
                        fg: DS.Color.accent,
                        bg: DS.Color.accent.opacity(0.10)
                    ) {
                        withAnimation(DS.Anim.snappy) {
                            selectedIds = allSelected ? [] : allIds
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }

                    // مقروء
                    pillButton(
                        icon: "envelope.open.fill",
                        label: L10n.t("مقروء", "Read"),
                        fg: DS.Color.textOnPrimary,
                        bg: selectedIds.isEmpty ? DS.Color.inactive : DS.Color.primary,
                        disabled: selectedIds.isEmpty
                    ) {
                        let ids = selectedIds
                        withAnimation(DS.Anim.snappy) { selectedIds.removeAll(); isSelecting = false }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task { await notificationVM.markNotificationsAsRead(ids: ids) }
                    }

                    // حذف — المدير والمالك فقط
                    if authVM.isAdmin {
                        pillButton(
                            icon: "trash.fill",
                            label: L10n.t("حذف", "Delete"),
                            fg: DS.Color.textOnPrimary,
                            bg: selectedIds.isEmpty ? DS.Color.inactive : DS.Color.error,
                            disabled: selectedIds.isEmpty
                        ) {
                            let ids = selectedIds
                            withAnimation(DS.Anim.snappy) { selectedIds.removeAll(); isSelecting = false }
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            Task { await notificationVM.deleteNotifications(ids: ids) }
                        }
                    }

                    // عداد المحدد
                    if !selectedIds.isEmpty {
                        Text("\(selectedIds.count)")
                            .font(DS.Font.scaled(11, weight: .black))
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(minWidth: NotifLayout.badgeSize, minHeight: NotifLayout.badgeSize)
                            .background(DS.Color.primary)
                            .clipShape(Circle())
                    }

                } else {
                    // ── الوضع العادي ──

                    // تحديد
                    if !filteredNotifications.isEmpty {
                        pillButton(
                            icon: "checklist.unchecked",
                            label: L10n.t("تحديد", "Select"),
                            fg: DS.Color.accent,
                            bg: DS.Color.accent.opacity(0.10)
                        ) {
                            withAnimation(DS.Anim.snappy) { isSelecting = true; selectedIds.removeAll() }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }

                    // قراءة الكل
                    if unreadCount > 0 {
                        pillButton(
                            icon: "envelope.open.fill",
                            label: L10n.t("قراءة الكل", "Read All"),
                            fg: DS.Color.primary,
                            bg: DS.Color.primary.opacity(0.10)
                        ) {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            Task { await notificationVM.markAllNotificationsAsRead() }
                        }
                    }

                    // عداد غير المقروء — كبسولة محايدة + الرقم في badge منفصل
                    if unreadCount > 0 {
                        HStack(spacing: DS.Spacing.xs) {
                            Text("\(unreadCount)")
                                .font(DS.Font.scaled(11, weight: .black))
                                .foregroundColor(DS.Color.textOnPrimary)
                                .frame(minWidth: 18, minHeight: 18)
                                .padding(.horizontal, 4)
                                .background(Capsule().fill(DS.Color.primary))
                            Text(L10n.t("غير مقروء", "unread"))
                                .font(DS.Font.scaled(11, weight: .semibold))
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(DS.Color.textTertiary.opacity(0.10))
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
        .padding(.vertical, DS.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.textTertiary.opacity(0.1)).frame(height: 0.5)
        }
        .animation(DS.Anim.snappy, value: isSelecting)
        .animation(DS.Anim.snappy, value: selectedIds.count)
    }

    // MARK: - Pill Button

    private func pillButton(
        icon: String,
        label: String,
        fg: Color,
        bg: Color,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xs) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(12, weight: .semibold))
                Text(label)
                    .font(DS.Font.scaled(12, weight: .bold))
            }
            .foregroundColor(fg)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .background(bg)
            .clipShape(Capsule())
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    // MARK: - Filtered Notifications

    private var hiddenKinds: Set<String> {
        var kinds = Set<String>()
        if !notifComments { kinds.insert("news_comment") }
        if !notifLikes { kinds.insert("news_like") }
        if !notifProfileUpdates { kinds.insert("profile_update") }
        return kinds
    }

    // MARK: - Segmented Tab Bar (sliding indicator)

    private func segmentedTabBar(notifCount: Int, activityCount: Int) -> some View {
        HStack(spacing: 2) {
            segmentTab(
                icon: "bell.badge.fill",
                title: L10n.t("الإشعارات", "Notifications"),
                count: notifCount,
                tab: .notifications
            )
            segmentTab(
                icon: "sparkles",
                title: L10n.t("المستجدات", "Activity"),
                count: activityCount,
                tab: .activity
            )
        }
        .padding(3)
        .fixedSize(horizontal: false, vertical: true)
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private func segmentTab(icon: String, title: String, count: Int, tab: NotifTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                selectedTab = tab
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            ZStack {
                // مؤشر الاختيار المتحرك (sliding indicator)
                if isSelected {
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .fill(DS.Color.gradientPrimary)
                        .shadow(color: DS.Color.primary.opacity(0.3), radius: 6, x: 0, y: 2)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabIndicator)
                }

                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .symbolRenderingMode(.hierarchical)

                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(isSelected ? DS.Color.primary : DS.Color.textOnPrimary)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, 3)
                            .background(
                                Capsule()
                                    .fill(isSelected ? Color.white : DS.Color.error)
                            )
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .foregroundColor(isSelected ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// إجراءات تمّت — تظهر في تاب "المستجدات" للأدمن فقط (موافقة/رفض/تعديل/تفعيل/نشر)
    private static let completedActionKinds: Set<String> = [
        // تعديلات أدمن مباشرة
        NotificationKind.adminEdit.rawValue,
        NotificationKind.adminEditName.rawValue,
        NotificationKind.adminEditDates.rawValue,
        NotificationKind.adminEditPhone.rawValue,
        NotificationKind.adminEditPhoneRemove.rawValue,
        NotificationKind.adminEditRole.rawValue,
        NotificationKind.adminEditFather.rawValue,
        NotificationKind.adminEditAvatar.rawValue,
        NotificationKind.adminEditAvatarRemove.rawValue,
        NotificationKind.adminEditChildAdd.rawValue,
        NotificationKind.adminEditChildRemove.rawValue,
        NotificationKind.memberDelete.rawValue,
        // عضوية (تم تفعيل)
        NotificationKind.joinApproved.rawValue,
        NotificationKind.accountActivated.rawValue,
        NotificationKind.roleChange.rawValue,
        // موافقات/رفض على إجراءات
        NotificationKind.diwaniyaApproved.rawValue,
        NotificationKind.diwaniyaRejected.rawValue,
        NotificationKind.projectApproved.rawValue,
        NotificationKind.projectRejected.rawValue,
        NotificationKind.storyApproved.rawValue,
        NotificationKind.storyRejected.rawValue,
        NotificationKind.galleryApproved.rawValue,
        NotificationKind.galleryRejected.rawValue,
        // نشر محتوى
        NotificationKind.newsPublished.rawValue,
        // حذف محتوى (إجراء منفّذ — مو طلب معلّق)
        "news_deleted",
    ]

    /// كل الإشعارات بعد تطبيق فلتر الإعدادات (الأنواع المخفية)
    private var visibleNotifications: [AppNotification] {
        let all = notificationVM.notifications
        guard !hiddenKinds.isEmpty else { return all }
        return all.filter { !hiddenKinds.contains($0.kind) }
    }

    /// تاب "إشعاراتي":
    /// - الطلبات اللي تنتظر موافقتي (للأدمن)
    /// - الإشعارات الموجّهة لي شخصياً (ليست إجراءً تمّ على آخرين)
    /// - الإشعارات اليتيمة (kind غير معروف وغير موجّهة لشخص محدد) — كانت
    ///   تختفي قبل، الآن تظهر هنا عشان المستخدم يقدر يقرأها/يحذفها
    private func belongsToNotificationsTab(_ n: AppNotification) -> Bool {
        let myId = authVM.currentUser?.id
        let isCompletedAction = Self.completedActionKinds.contains(n.kind)
        let isPendingApproval = Self.pendingApprovalKinds.contains(n.kind)

        // عناوين تبدأ بـ "تم قبول/تم رفض" أو "Approved/Rejected" تدل على إجراء منفّذ
        // (يستخدم لتمييز broadcastCompletedAction عن الطلبات الأصلية بنفس الـ kind)
        let titleIndicatesCompleted = n.title.hasPrefix("تم قبول")
            || n.title.hasPrefix("تم رفض")
            || n.title.contains("Approved")
            || n.title.contains("Rejected")

        // للأدمن: الإجراءات اللي تمّت تذهب لـ "المستجدات" (مو "إشعاراتي")
        if authVM.canModerate && (isCompletedAction || titleIndicatesCompleted) { return false }

        // طلبات تنتظر موافقة الأدمن
        if isPendingApproval { return true }

        // إشعار موجّه لي شخصياً (نتيجة موافقة/رفض/تعليق على شيء يخصني)
        if n.targetMemberId == myId { return true }

        // إشعار يتيم: kind غير معروف ولا موجّه لشخص محدد
        // (للأدمن: لازم يكون مو completed action عشان لا يتداخل مع تاب المستجدات)
        let isOrphan = !isPendingApproval && !isCompletedAction && !titleIndicatesCompleted
        if isOrphan, n.targetMemberId == nil {
            return true
        }
        return false
    }

    /// أنواع الطلبات الجديدة اللي تنتظر موافقة الأدمن — تظهر في "إشعاراتي" فقط
    private static let pendingApprovalKinds: Set<String> = [
        NotificationKind.adminRequest.rawValue,
        NotificationKind.linkRequest.rawValue,
        NotificationKind.newsReport.rawValue,
        NotificationKind.treeEdit.rawValue,
        NotificationKind.deceasedReport.rawValue,
        NotificationKind.childAdd.rawValue,
        NotificationKind.phoneChange.rawValue,
        NotificationKind.nameChange.rawValue,
        NotificationKind.photoSuggestion.rawValue,
        NotificationKind.galleryPending.rawValue,
        NotificationKind.storyPending.rawValue,
        NotificationKind.diwaniyaPending.rawValue,
        NotificationKind.projectPending.rawValue,
        NotificationKind.newsAdd.rawValue,
        NotificationKind.contactMessage.rawValue,
    ]

    /// تاب "المستجدات" (للأدمن فقط): الإجراءات اللي تمّت
    private func belongsToActivityTab(_ n: AppNotification) -> Bool {
        guard !belongsToNotificationsTab(n) else { return false }
        let titleIndicatesCompleted = n.title.hasPrefix("تم قبول")
            || n.title.hasPrefix("تم رفض")
            || n.title.contains("Approved")
            || n.title.contains("Rejected")
        return Self.completedActionKinds.contains(n.kind) || titleIndicatesCompleted
    }

    private var filteredNotifications: [AppNotification] {
        let visible = visibleNotifications
        switch selectedTab {
        case .notifications: return visible.filter(belongsToNotificationsTab)
        case .activity:      return visible.filter(belongsToActivityTab)
        }
    }

    // MARK: - Date Grouping

    private func dateSection(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.t("اليوم", "Today")
        } else if calendar.isDateInYesterday(date) {
            return L10n.t("أمس", "Yesterday")
        } else if let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
                  date >= weekStart {
            return L10n.t("هذا الأسبوع", "This Week")
        } else {
            return L10n.t("أقدم", "Older")
        }
    }

    private var groupedNotifications: [(String, [AppNotification])] {
        let sorted = filteredNotifications.sorted { $0.createdDate > $1.createdDate }
        let grouped = Dictionary(grouping: sorted) { dateSection(for: $0.createdDate) }
        let order = [
            L10n.t("اليوم", "Today"),
            L10n.t("أمس", "Yesterday"),
            L10n.t("هذا الأسبوع", "This Week"),
            L10n.t("أقدم", "Older")
        ]
        return order.compactMap { section in
            guard let items = grouped[section], !items.isEmpty else { return nil }
            return (section, items)
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        List {
            ForEach(groupedNotifications, id: \.0) { section, items in
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let iconInfo = NotificationKindStyle.style(for: item.kind)
                        let isUnread = !item.read

                        notificationRow(item: item, iconInfo: iconInfo, isUnread: isUnread)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(DS.Anim.smooth.delay(Double(min(index, 5)) * 0.04), value: appeared)
                            .listRowInsets(EdgeInsets(top: 3, leading: DS.Spacing.lg, bottom: 3, trailing: DS.Spacing.lg))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: authVM.isAdmin) {
                                if authVM.isAdmin {
                                    Button(role: .destructive) {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        Task { await notificationVM.deleteNotification(id: item.id) }
                                    } label: {
                                        Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if isUnread {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        Task { await notificationVM.markNotificationAsRead(id: item.id) }
                                    } label: {
                                        Label(L10n.t("مقروء", "Read"), systemImage: "envelope.open")
                                    }
                                    .tint(DS.Color.primary)
                                }
                            }
                    }
                } header: {
                    HStack(spacing: DS.Spacing.sm) {
                        Text(section)
                            .font(DS.Font.scaled(12, weight: .bold))
                            .foregroundColor(DS.Color.textSecondary)
                        Rectangle()
                            .fill(DS.Color.textTertiary.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 3)
                    .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 2, trailing: DS.Spacing.lg))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await notificationVM.fetchNotifications(force: true)
        }
    }

    // MARK: - Notification Row

    private func notificationRow(item: AppNotification, iconInfo: NotificationKindStyle, isUnread: Bool) -> some View {
        Button {
            if isSelecting {
                withAnimation(DS.Anim.snappy) {
                    if selectedIds.contains(item.id) {
                        selectedIds.remove(item.id)
                    } else {
                        _ = selectedIds.insert(item.id)
                    }
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } else {
                selectedNotification = item
                if isUnread {
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
                }
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                // Checkbox في وضع التحديد
                if isSelecting {
                    let isSelected = selectedIds.contains(item.id)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(DS.Font.scaled(22, weight: .medium))
                        .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.textTertiary)
                        .animation(DS.Anim.snappy, value: isSelected)
                }

                // أيقونة النوع — دائرة كبيرة
                ZStack {
                    Circle()
                        .fill(isUnread ? iconInfo.color.opacity(0.12) : DS.Color.textTertiary.opacity(0.08))
                        .frame(width: NotifLayout.rowIconSize, height: NotifLayout.rowIconSize)

                    Image(systemName: iconInfo.icon)
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(isUnread ? iconInfo.color : DS.Color.textTertiary)
                }

                // المحتوى
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    // العنوان + الوقت
                    HStack(alignment: .top) {
                        Text(item.title)
                            .font(DS.Font.scaled(15, weight: isUnread ? .bold : .medium))
                            .foregroundColor(isUnread ? DS.Color.textPrimary : DS.Color.textTertiary)
                            .lineLimit(2)

                        Spacer(minLength: DS.Spacing.sm)

                        Text(relativeTime(item.createdDate))
                            .font(DS.Font.scaled(11, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                    }

                    // النص الكامل
                    richBodyView(
                        item.body,
                        font: DS.Font.scaled(13, weight: .regular),
                        color: isUnread ? DS.Color.textSecondary : DS.Color.textTertiary,
                        lineLimit: 3
                    )

                    // شريط سفلي: التصنيف + بادج المدير
                    HStack(spacing: DS.Spacing.sm) {
                        // التصنيف
                        Text(iconInfo.label)
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(isUnread ? iconInfo.color : DS.Color.textTertiary)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background((isUnread ? iconInfo.color : DS.Color.textTertiary).opacity(0.08))
                            .clipShape(Capsule())

                        // اسم المرسل — إداري يعرض "الإدارة"
                        if authVM.isAdmin, let creatorId = item.createdBy {
                            let isAdminNotif = Self.completedActionKinds.contains(item.kind)
                            let creator = memberVM.member(byId: creatorId)
                            // في القائمة: نُبقي "الإدارة" كاسم مُعمَّم لإشعارات تعديل المدير
                            // (الاسم الفعلي يظهر فقط داخل sheet التفاصيل، للمدراء فقط)
                            let creatorName = isAdminNotif
                                ? L10n.t("الإدارة", "Admin")
                                : (creator?.shortFullName ?? L10n.t("الإدارة", "Admin"))
                            let roleColor: Color = isAdminNotif ? DS.Color.primary : (creator?.roleColor ?? DS.Color.accent)

                            HStack(spacing: 3) {
                                Circle()
                                    .fill(roleColor)
                                    .frame(width: 6, height: 6)
                                Text(creatorName)
                                    .font(DS.Font.scaled(10, weight: .bold))
                            }
                            .foregroundColor(roleColor)
                            .padding(.horizontal, DS.Spacing.sm)
                            .padding(.vertical, 2)
                            .background(roleColor.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(roleColor.opacity(0.2), lineWidth: 0.5))
                        }

                        Spacer(minLength: 0)
                        // أزرار الموافقة/الرفض السريعة أُزيلت من صف الإشعار —
                        // الإجراءات تتم من شاشة تفاصيل الإشعار أو من لوحة الإدارة.
                    }
                }

                // نقطة غير مقروء
                if isUnread && !isSelecting {
                    Circle()
                        .fill(DS.Color.primary)
                        .frame(width: 9, height: 9)
                }
            }
            .padding(DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                    .stroke(
                        isUnread ? iconInfo.color.opacity(0.15) : DS.Color.textTertiary.opacity(0.08),
                        lineWidth: isUnread ? 1 : 0.5
                    )
            )
            .dsSubtleShadow()
            .opacity(isUnread ? 1 : 0.55)
        }
        .buttonStyle(DSScaleButtonStyle())
        .contextMenu {
            if isUnread {
                Button {
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
                } label: {
                    Label(L10n.t("تعليم كمقروء", "Mark as Read"), systemImage: "envelope.open")
                }
            }
            if authVM.isAdmin {
                Button(role: .destructive) {
                    Task { await notificationVM.deleteNotification(id: item.id) }
                } label: {
                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let isActivity = authVM.isAdmin && selectedTab == .activity
        return DSEmptyState(
            icon: isActivity ? "sparkles" : "bell.slash.fill",
            title: isActivity
                ? L10n.t("لا يوجد نشاط", "No Activity")
                : L10n.t("لا توجد إشعارات", "No Notifications"),
            subtitle: isActivity
                ? L10n.t("نشاط النظام يظهر هنا", "System activity appears here")
                : L10n.t("الإشعارات الموجهة لك تظهر هنا", "Notifications for you appear here"),
            style: .halo
        )
    }

    // MARK: - Detail Sheet

    private func notificationDetailSheet(_ notification: AppNotification) -> some View {
        let iconInfo = NotificationKindStyle.style(for: notification.kind)
        let date = notification.createdDate
        let relatedMember = relatedMemberForNotification(notification)
        let isJoinRequest = notification.kind == RequestType.joinRequest.rawValue
            || notification.kind == NotificationKind.linkRequest.rawValue

        return ZStack {
            DS.Color.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: relatedMember == nil ? DS.Spacing.sm : DS.Spacing.md) {
                    detailHero(notification: notification, iconInfo: iconInfo, date: date)
                        .padding(.top, isLandscape ? DS.Spacing.lg : DS.Spacing.xxxl)

                    if let member = relatedMember {
                        detailMemberCard(member: member, iconInfo: iconInfo)
                    }

                    // قسم التطابقات المحتملة — كارد مستقل قبل جسم الإشعار للأهمية
                    // ملاحظة: الإشعارات اللي من trigger تحفظ pending ID في created_by،
                    // والإشعارات من admin_requests تحفظه في request_id — نستخدم fallback
                    let showMatchesSection = isJoinRequest && authVM.canModerate
                    let resolvedRequesterId = notification.requestId ?? notification.createdBy
                    if showMatchesSection, let requesterId = resolvedRequesterId {
                        joinMatchesCard(
                            candidates: joinMatchCandidates,
                            requesterId: requesterId,
                            iconInfo: iconInfo,
                            isLoading: !joinMatchesLoaded
                        )
                    }

                    if !notification.body.isEmpty {
                        detailBodyCard(
                            notification: notification,
                            iconInfo: iconInfo
                        )
                    }

                    if authVM.isAdmin,
                       let details = notification.details,
                       !details.changes.isEmpty {
                        DSChangeDetailsCard(details: details)
                    }

                    detailActions(notification: notification)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xs)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: DetailSheetHeightKey.self, value: geo.size.height)
                    }
                )
            }
        }
        .onPreferenceChange(DetailSheetHeightKey.self) { newContentHeight in
            // buffer: bottom safe area (~34pt) + grabber — تم تقليله لتقليل الفراغ تحت الأزرار
            let target = newContentHeight + 16
            let screenH = UIScreen.main.bounds.height
            let cap = screenH - 60
            let clamped = max(280, min(target, cap))
            if abs(clamped - measuredDetailHeight) > 2 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    measuredDetailHeight = clamped
                    detailSheetDetent = .height(clamped)
                }
            }
        }
        .task(id: notification.id) {
            joinMatchesExpanded = false
            joinMatchesLoaded = false
            await loadJoinMatchCandidates(for: notification)
            joinMatchesLoaded = true
        }
        .confirmationDialog(
            L10n.t("اختر طريقة الموافقة", "Choose approval method"),
            isPresented: Binding(
                get: { joinApproveDialog != nil },
                set: { if !$0 { joinApproveDialog = nil } }
            ),
            titleVisibility: .visible,
            presenting: joinApproveDialog
        ) { activeNotification in
            ForEach(joinMatchCandidates.prefix(8)) { candidate in
                Button(L10n.t("ربط مع: ", "Link with: ") + chainFourNames(candidate)) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let nid = activeNotification.id
                    guard let rid = activeNotification.requestId else {
                        joinApproveDialog = nil
                        return
                    }
                    // ⚠️ لا تربط مباشرة — أظهر alert تأكيد (الإجراء غير قابل للتراجع)
                    joinApproveDialog = nil
                    linkConfirmTarget = LinkConfirmation(
                        notificationId: nid,
                        requesterId: rid,
                        candidate: candidate
                    )
                }
            }
            Button(L10n.t("الموافقة كعضو جديد", "Approve as new member")) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let nid = activeNotification.id
                let n = activeNotification
                joinApproveDialog = nil
                selectedNotification = nil
                Task {
                    _ = await notificationVM.approveRequestFromNotification(n)
                    await notificationVM.markNotificationAsRead(id: nid)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                joinApproveDialog = nil
            }
        } message: { _ in
            Text(L10n.t(
                "وُجدت \(joinMatchCandidates.count) تطابقات بنفس الاسم في الشجرة. اربطه بأحدهم أو أنشئه كعضو جديد.",
                "\(joinMatchCandidates.count) matches found in the tree. Link to one of them or approve as a new member."
            ))
        }
        .alert(
            L10n.t("تأكيد الربط", "Confirm Link"),
            isPresented: Binding(
                get: { linkConfirmTarget != nil },
                set: { if !$0 { linkConfirmTarget = nil } }
            ),
            presenting: linkConfirmTarget
        ) { target in
            Button(L10n.t("تأكيد الربط", "Link"), role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                let nid = target.notificationId
                let requesterId = target.requesterId
                let candidateId = target.candidate.id
                linkConfirmTarget = nil
                selectedNotification = nil
                // نظّف نتيجة الدمج السابقة قبل الاستدعاء عشان التنبيه يطلق بس على النتيجة الجديدة
                adminRequestVM.mergeResult = nil
                Task {
                    await adminRequestVM.mergeMemberIntoTreeMember(
                        newMemberId: requesterId,
                        existingTreeMemberId: candidateId
                    )
                    await notificationVM.markNotificationAsRead(id: nid)
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                linkConfirmTarget = nil
            }
        } message: { target in
            Text(L10n.t(
                "هل تريد ربط طلب الانضمام بـ \(chainFourNames(target.candidate))؟\n\nسيتم دمج البيانات في حساب موجود ولا يمكن التراجع.",
                "Link this join request to \(chainFourNames(target.candidate))?\n\nData will be merged into an existing account and cannot be undone."
            ))
        }
        .presentationDetents([.height(measuredDetailHeight), .large], selection: $detailSheetDetent)
        .presentationDragIndicator(.visible)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// اسم رباعي — wrapper للـcomputed property على FamilyMember
    /// (يبقى local helper عشان call sites الموجودة ما تحتاج تغيير)
    private func fourPartName(_ member: FamilyMember) -> String {
        member.fourPartName
    }

    /// أربع كلمات من السلسلة (الأول + الثاني + الثالث + الرابع)
    /// يُستخدم في عرض التطابقات وحوار الربط ليُعطي سلسلة نسب فعلية بدون اسم العائلة.
    private func chainFourNames(_ member: FamilyMember) -> String {
        member.chainFourNames
    }

    /// يحدّد العضو الأكثر صلة بالإشعار (الأهم بصرياً) — لعرض بطاقة العضو في تفاصيل الإشعار
    /// - للطلبات: مقدّم الطلب (createdBy) لو معروف وموجود
    /// - للإشعارات الشخصية: المرسل (createdBy) لو معروف وليس مدير
    private func relatedMemberForNotification(_ n: AppNotification) -> FamilyMember? {
        // إشعار تحديث صورة عضو في «المستجدات» — نعرض العضو صاحب الصورة (الاسم + الصورة
        // المحدّثة): العضو الهدف لو موجود (تعديل المدير)، وإلا المُنفّذ (العضو حدّث صورته بنفسه).
        if n.kind == NotificationKind.adminEditAvatar.rawValue {
            if let tid = n.targetMemberId, let m = memberVM.member(byId: tid) { return m }
            if let cid = n.createdBy, let m = memberVM.member(byId: cid) { return m }
            return nil
        }
        // استبعاد إشعارات الإدارة المُعمَّمة — اسم الشخص لا يهم
        if adminOnlyKinds.contains(n.kind) { return nil }
        guard let creatorId = n.createdBy,
              creatorId != authVM.currentUser?.id else { return nil }
        return memberVM.member(byId: creatorId)
    }

    /// قائمة kinds التي تُعرض كـ "الإدارة" بدل اسم الشخص — متطابقة مع منطق row/hero
    private var adminOnlyKinds: Set<String> {
        Self.completedActionKinds.union([
            NotificationKind.adminEdit.rawValue,
            NotificationKind.adminEditName.rawValue,
            NotificationKind.adminEditDates.rawValue,
            NotificationKind.adminEditPhone.rawValue,
            NotificationKind.adminEditRole.rawValue,
            NotificationKind.adminEditFather.rawValue,
            NotificationKind.adminEditAvatar.rawValue,
            NotificationKind.adminEditChildAdd.rawValue,
            NotificationKind.adminEditChildRemove.rawValue,
            // الإعلانات العامة — اسم المرسِل ليس "موضوع" الإشعار
            "admin",
            "admin_broadcast",
        ])
    }

    // MARK: - Detail: Hero (compact horizontal)
    private func detailHero(notification: AppNotification, iconInfo: NotificationKindStyle, date: Date) -> some View {
        return HStack(alignment: .center, spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(iconInfo.gradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: iconInfo.color.opacity(0.30), radius: 10, x: 0, y: 4)
                Image(systemName: iconInfo.icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(notification.title)
                    .font(DS.Font.scaled(18, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(relativeTime(date))
                    .font(DS.Font.scaled(12, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Detail: Member Card (صورة + اسم + دور)
    private func detailMemberCard(member: FamilyMember, iconInfo: NotificationKindStyle) -> some View {
        Button {
            selectedMember = member
        } label: {
            detailMemberCardBody(member: member, iconInfo: iconInfo)
        }
        .buttonStyle(.plain)
        .sheet(item: $selectedMember) { m in
            NavigationStack { MemberDetailsView(member: m) }
                .presentationDetents([.fraction(0.42), .large])
                .presentationDragIndicator(.visible)
                .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private func detailMemberCardBody(member: FamilyMember, iconInfo: NotificationKindStyle) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // صورة العضو (دائرية)
            ZStack {
                Circle()
                    .fill(DS.Color.textTertiary.opacity(0.08))
                    .frame(width: 48, height: 48)

                if let url = member.avatarUrl, !url.isEmpty {
                    CachedAsyncImage(url: URL(string: url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(18, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(fourPartName(member))
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // رقاقة الدور
                Text(member.roleName)
                    .font(DS.Font.scaled(10, weight: .bold))
                    .foregroundColor(member.roleColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(member.roleColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            // سهم — إشارة أن الكرت يفتح تفاصيل العضو
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(DS.Font.scaled(12, weight: .bold))
                .foregroundColor(DS.Color.textTertiary.opacity(0.6))

            // أيقونة صغيرة تشير لنوع الإشعار
            Image(systemName: iconInfo.icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(iconInfo.color)
                .padding(8)
                .background(iconInfo.color.opacity(0.10))
                .clipShape(Circle())
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(member.roleColor.opacity(0.20), lineWidth: 0.5)
        )
        .dsSubtleShadow()
    }

    // MARK: - Detail: Body Card (نص الإشعار) — مُحسَّن
    private func detailBodyCard(
        notification: AppNotification,
        iconInfo: NotificationKindStyle
    ) -> some View {
        let date = notification.createdDate
        // اسم المدير المنفّذ — يظهر داخل تفاصيل الإشعار حتى للأنواع المُعمَّمة (admin_edit_*)
        // لكن إشعارات الإدارة المُرسَلة (admin_broadcast/admin) تظهر باسم «الإدارة» لا باسم شخصي.
        let isAdminSender = adminOnlyKinds.contains(notification.kind)
        let actualCreator: FamilyMember? = {
            guard !isAdminSender, authVM.isAdmin,
                  let creatorId = notification.createdBy else { return nil }
            return memberVM.member(byId: creatorId)
        }()

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // ترويسة: chip التصنيف + chip المدير المنفّذ + الحالة
            HStack(spacing: DS.Spacing.xs) {
                // chip التصنيف
                HStack(spacing: 4) {
                    Image(systemName: iconInfo.icon)
                        .font(DS.Font.scaled(10, weight: .bold))
                    Text(iconInfo.label)
                        .font(DS.Font.scaled(10, weight: .bold))
                }
                .foregroundColor(iconInfo.color)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(iconInfo.color.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(iconInfo.color.opacity(0.20), lineWidth: 0.5))

                // chip «الإدارة» — لإشعارات الإدارة المُرسَلة (بدون اسم شخصي)
                if isAdminSender {
                    HStack(spacing: 3) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(DS.Font.scaled(9, weight: .bold))
                        Text(L10n.t("الإدارة", "Admin"))
                            .font(DS.Font.scaled(10, weight: .bold))
                    }
                    .foregroundColor(DS.Color.primary)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(DS.Color.primary.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Color.primary.opacity(0.20), lineWidth: 0.5))
                }

                // chip المدير المنفّذ — للأدمن فقط، اسم حقيقي مو "الإدارة"
                if let creator = actualCreator {
                    HStack(spacing: 3) {
                        Image(systemName: "person.fill")
                            .font(DS.Font.scaled(9, weight: .bold))
                        Text(creator.shortFullName)
                            .font(DS.Font.scaled(10, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundColor(creator.roleColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(creator.roleColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(creator.roleColor.opacity(0.20), lineWidth: 0.5))
                    .layoutPriority(-1)
                }

                Spacer(minLength: 0)

                // حالة القراءة كنقطة ملونة + نص صغير
                HStack(spacing: 4) {
                    Circle()
                        .fill(notification.read ? DS.Color.textTertiary : DS.Color.primary)
                        .frame(width: 6, height: 6)
                    Text(notification.read ? L10n.t("مقروء", "Read") : L10n.t("جديد", "New"))
                        .font(DS.Font.scaled(10, weight: .bold))
                        .foregroundColor(notification.read ? DS.Color.textTertiary : DS.Color.primary)
                }
            }

            // معاينة "قبل → بعد" — تظهر فقط للإشعارات اللي تحمل تفاصيل تغيير
            if let firstChange = notification.details?.changes.first {
                detailFromToInline(change: firstChange, color: iconInfo.color)
            }

            // المحتوى الأساسي — للإعلانات الإدارية يُعرض بشكل بارز (نص أكبر +
            // علامة اقتباس على الحافة) لأن الرسالة نفسها هي محتوى الإشعار.
            let isBroadcast = (notification.kind == "admin" || notification.kind == "admin_broadcast")
            let bodyText = bodyWithoutCreatorPrefix(notification.body, creator: actualCreator)

            // للإعلانات: نص أكبر قليلاً عشان الرسالة هي محتوى الإشعار.
            richBodyView(
                bodyText,
                font: DS.Font.scaled(isBroadcast ? 17 : 15, weight: isBroadcast ? .semibold : .regular),
                color: DS.Color.textPrimary
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            // التاريخ والوقت الكامل (تذييل خفيف)
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(DS.Font.scaled(10, weight: .semibold))
                Text(fullDateTime(date))
                    .font(DS.Font.scaled(11, weight: .medium))
            }
            .foregroundColor(DS.Color.textTertiary)
            .padding(.top, DS.Spacing.xs)


        }
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.10), lineWidth: 0.5)
        )
        .dsSubtleShadow()
    }

    // MARK: - Detail: Matches Card (كارد التطابقات المحتملة)
    private func joinMatchesCard(
        candidates: [FamilyMember],
        requesterId: UUID,
        iconInfo: NotificationKindStyle,
        isLoading: Bool
    ) -> some View {
        joinMatchesSection(
            candidates: candidates,
            requesterId: requesterId,
            iconInfo: iconInfo,
            isLoading: isLoading
        )
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(iconInfo.color.opacity(0.20), lineWidth: 0.5)
        )
        .dsSubtleShadow()
    }


    /// معاينة "قبل → بعد" مدمجة — تظهر داخل كرت التفاصيل لإشعارات admin_edit_*
    @ViewBuilder
    private func detailFromToInline(change: AppNotification.NotificationDetails.ChangeEntry, color: Color) -> some View {
        let isOpaque = AppNotification.NotificationDetails.isOpaqueField(change.field)
        let fieldLabel = AppNotification.NotificationDetails.localizedFieldName(change.field)

        HStack(spacing: 6) {
            // اسم الحقل
            Text(fieldLabel)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)

            Text("·")
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)

            if isOpaque {
                // للحقول التي لا تُعرض قيمتها (مثل الصورة): "تم التحديث"
                Text(L10n.t("تم التحديث", "Updated"))
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            } else {
                // قيمة قبل
                Text(change.before ?? "—")
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.error.opacity(0.85))
                    .strikethrough()
                    .lineLimit(1)

                // سهم
                Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                    .font(DS.Font.scaled(9, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)

                // قيمة بعد
                Text(change.after ?? "—")
                    .font(DS.Font.scaled(11, weight: .bold))
                    .foregroundColor(DS.Color.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 6)
        .background(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(color.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func detailChip(text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(DS.Font.scaled(10, weight: .bold))
            }
            Text(text)
                .font(DS.Font.scaled(11, weight: .bold))
        }
        .foregroundColor(color)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, 5)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: - Detail: Content card
    private func detailContentCard(notification: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("المحتوى", "Content"))
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .textCase(.uppercase)

            richBodyView(
                notification.body,
                font: DS.Font.scaled(15, weight: .regular),
                color: DS.Color.textPrimary
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DS.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 0.5)
        )
        .dsSubtleShadow()
    }

    // MARK: - Detail: Meta card
    private func detailMetaCard(notification: AppNotification, iconInfo: NotificationKindStyle, date: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("التفاصيل", "Details"))
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.lg)

            VStack(spacing: 0) {
                detailInfoRow(
                    icon: "calendar.badge.clock",
                    label: L10n.t("التاريخ", "Date"),
                    value: fullDateTime(date),
                    color: DS.Color.primary
                )

                if authVM.isAdmin, let creatorId = notification.createdBy {
                    let isAdminNotif = Self.completedActionKinds.contains(notification.kind)
                    let creator = memberVM.member(byId: creatorId)
                    // داخل sheet التفاصيل (للمدراء فقط — gate isAdmin أعلاه): اعرض
                    // الاسم الفعلي للشخص اللي عدّل + المنصب، عشان يتميّز بين المدراء.
                    // الأعضاء العاديون أصلاً ما يدخلون هنا (محجوب بـauthVM.isAdmin).
                    let creatorName: String = {
                        guard let creator = creator else { return L10n.t("الإدارة", "Admin") }
                        return isAdminNotif
                            ? "\(creator.roleName) \(creator.shortFullName)"
                            : creator.shortFullName
                    }()
                    let roleColor: Color = (creator?.roleColor ?? DS.Color.primary)

                    detailDivider
                    HStack(spacing: DS.Spacing.md) {
                        Circle()
                            .fill(roleColor)
                            .frame(width: 10, height: 10)
                            .frame(width: NotifLayout.infoIconWidth, alignment: .center)

                        Text(L10n.t("بواسطة", "By"))
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: 80, alignment: .leading)

                        Text(creatorName)
                            .font(DS.Font.scaled(13, weight: .bold))
                            .foregroundColor(roleColor)

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.md)
                }

                if authVM.isAdmin {
                    detailDivider
                    detailInfoRow(
                        icon: "tag.fill",
                        label: L10n.t("التصنيف", "Category"),
                        value: iconInfo.label,
                        color: iconInfo.color
                    )
                }
            }
        }
        .padding(.bottom, DS.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.1), lineWidth: 0.5)
        )
        .dsSubtleShadow()
    }

    // MARK: - Detail: Actions (circular icon buttons)
    @ViewBuilder
    private func detailActions(notification: AppNotification) -> some View {
        let isRequest = authVM.isAdmin
            && (notification.isActionableRequest || Self.pendingApprovalKinds.contains(notification.kind))

        VStack(spacing: DS.Spacing.md) {
            // الأزرار الدائرية: موافقة / رفض / مراجعة / حذف
            HStack(spacing: DS.Spacing.xl) {
                if isRequest {
                    detailCircleAction(
                        icon: "checkmark",
                        color: DS.Color.secondary,
                        label: L10n.t("موافقة", "Approve")
                    ) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        // طلب انضمام/ربط + يوجد تطابقات → اعرض حوار اختيار
                        let isJoinKind = notification.kind == RequestType.joinRequest.rawValue
                            || notification.kind == NotificationKind.linkRequest.rawValue
                            || notification.kind == RequestType.linkRequest.rawValue
                        if isJoinKind && !joinMatchCandidates.isEmpty {
                            joinApproveDialog = notification
                            return
                        }
                        let id = notification.id
                        selectedNotification = nil
                        Task {
                            _ = await notificationVM.approveRequestFromNotification(notification)
                            await notificationVM.markNotificationAsRead(id: id)
                        }
                    }
                    detailCircleAction(
                        icon: "xmark",
                        color: DS.Color.error,
                        label: L10n.t("رفض", "Reject")
                    ) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        let id = notification.id
                        selectedNotification = nil
                        Task {
                            _ = await notificationVM.rejectRequestFromNotification(notification)
                            await notificationVM.markNotificationAsRead(id: id)
                        }
                    }
                    detailCircleAction(
                        icon: "shield.checkered",
                        color: DS.Color.accent,
                        label: L10n.t("المراجعة", "Review")
                    ) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        let kind = notification.kind
                        selectedNotification = nil
                        NotificationCenter.default.post(
                            name: .openAdminReviewForKind,
                            object: nil,
                            userInfo: ["kind": kind]
                        )
                    }
                }

                // زر الحذف — متاح دائماً، مدمج مع باقي الأزرار
                detailCircleAction(
                    icon: "trash",
                    color: DS.Color.textTertiary,
                    label: L10n.t("حذف", "Delete")
                ) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    let id = notification.id
                    selectedNotification = nil
                    Task { await notificationVM.deleteNotification(id: id) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DS.Spacing.sm)

            // تعليم كمقروء — كرابط نصي خفيف
            if !notification.read {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    let id = notification.id
                    selectedNotification = nil
                    Task { await notificationVM.markNotificationAsRead(id: id) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "envelope.open")
                            .font(DS.Font.scaled(11, weight: .semibold))
                        Text(L10n.t("تعليم كمقروء", "Mark as Read"))
                            .font(DS.Font.scaled(12, weight: .semibold))
                    }
                    .foregroundColor(DS.Color.primary)
                }
                .buttonStyle(DSScaleButtonStyle())
            }
        }
    }

    // MARK: - Phase 3: Join Request Match Card

    /// يحمّل قائمة الأعضاء المرشّحين كتطابقات لطلب الانضمام/الربط
    /// يظهر الكرت لو فيه عضو بنفس الاسم الأول في الشجرة
    private func loadJoinMatchCandidates(for notification: AppNotification) async {
        joinMatchCandidates = []

        let isJoinKind = notification.kind == RequestType.joinRequest.rawValue
            || notification.kind == NotificationKind.linkRequest.rawValue
            || notification.kind == RequestType.linkRequest.rawValue
        guard isJoinKind else {
            Log.info("[JoinMatch] skip — kind=\(notification.kind) ليس join/link")
            return
        }

        // 1) جرب المسار السريع: requester عبر requestId/createdBy
        var requester: FamilyMember? = nil
        if let rid = notification.requestId ?? notification.createdBy {
            requester = memberVM.member(byId: rid)
            if requester == nil {
                Log.info("[JoinMatch] requester \(rid.uuidString.prefix(8)) غير موجود في allMembers — سنحاول fetch")
                await memberVM.fetchAllMembers(force: true)
                requester = memberVM.member(byId: rid)
            }
        }

        // 2) استخرج الاسم الكامل للمتقدم من requester أو من body كـ fallback
        let fullName: String = {
            if let r = requester, !r.fullName.trimmingCharacters(in: .whitespaces).isEmpty {
                return r.fullName.trimmingCharacters(in: .whitespaces)
            }
            // Body example: "عبدالله محمد مصطفى يطلب الانضمام للشجرة"
            // نأخذ كل النص قبل "يطلب"
            let body = notification.body
            if let range = body.range(of: "يطلب") {
                return String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return body.components(separatedBy: .whitespacesAndNewlines).first ?? ""
        }()

        guard !fullName.isEmpty else {
            Log.info("[JoinMatch] fullName فارغ — إلغاء")
            return
        }

        let requesterId2 = requester?.id

        // 3) المسار الأول: RPC السيرفر search_members_by_name (v2: exact word + 75% + top-4 parts)
        let serverMatchIds: [UUID] = await fetchServerMatches(fullName: fullName, excluding: requesterId2)

        // عضو "مرتبط بحساب" = عنده رقم هاتف غير فاضي (مؤشّر إنه سجّل ودخل التطبيق).
        // نستثنيه من المرشّحين لأنه أصلاً ربط حسابه — ما يصير ربط آخر معه.
        func isAlreadyLinked(_ m: FamilyMember) -> Bool {
            !(m.phoneNumber ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        }

        // 4) حول IDs إلى FamilyMember — مع استثناء المتوفّين والمُلحقين بحسابات
        var matches: [FamilyMember] = []
        for id in serverMatchIds {
            if let m = memberVM.member(byId: id),
               m.id != requesterId2,
               m.isDeceased != true,
               !isAlreadyLinked(m) {
                matches.append(m)
            }
        }

        // 5) Fallback محلي: لو السيرفر ما رجع شيء (مثلاً اسم من جزء واحد)،
        //    نستخدم المطابقة المحلية على أول كلمة، مع نفس الاستثناءات
        if matches.isEmpty {
            let firstName = fullName
                .components(separatedBy: .whitespacesAndNewlines)
                .first?
                .trimmingCharacters(in: CharacterSet.punctuationCharacters) ?? ""

            if !firstName.isEmpty {
                let localMatches = memberVM.allMembers.filter { candidate in
                    guard candidate.id != requesterId2 else { return false }
                    guard candidate.isDeceased != true else { return false }
                    guard !isAlreadyLinked(candidate) else { return false }
                    let candidateFirst = candidate.firstName
                        .components(separatedBy: .whitespacesAndNewlines)
                        .first?
                        .trimmingCharacters(in: CharacterSet.punctuationCharacters) ?? ""
                    return candidateFirst == firstName
                }
                matches = localMatches
                Log.info("[JoinMatch] السيرفر فاضي — fallback محلي على firstName='\(firstName)' أعطى \(matches.count)")
            }
        }

        // 6) استخراج سلسلة اسم المُسجِّل (عبدالله، محمد، مصطفى، الصايغ)
        //    من بروفايله لو موجود، أو من body كـ fallback
        let requesterChain: [String] = {
            if let r = requester {
                return r.fullName
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
            }
            let words = notification.body.components(separatedBy: .whitespacesAndNewlines)
            var chain: [String] = []
            for w in words {
                if w.contains("يطلب") || w.contains("requests") { break }
                let cleaned = w.trimmingCharacters(in: CharacterSet.punctuationCharacters)
                if !cleaned.isEmpty { chain.append(cleaned) }
            }
            return chain
        }()

        // تطبيع الاسم — يلغي الفروق الإملائية البسيطة:
        //   * يشيل المسافات داخل الاسم: "عبد الله" → "عبدالله"
        //   * يطبّع الألف والياء والتاء المربوطة
        func normalize(_ s: String) -> String {
            var n = s.replacingOccurrences(of: " ", with: "")
            n = n.replacingOccurrences(of: "أ", with: "ا")
            n = n.replacingOccurrences(of: "إ", with: "ا")
            n = n.replacingOccurrences(of: "آ", with: "ا")
            n = n.replacingOccurrences(of: "ى", with: "ي")
            n = n.replacingOccurrences(of: "ة", with: "ه")
            return n
        }

        let normalizedRequesterChain = requesterChain.map(normalize)

        // درجة التطابق بمقارنة 5 مواقع منفصلة:
        //   الأول + الثاني + الثالث + الرابع + الأخير (اسم العائلة).
        //   كل موقع متطابق = نقطة. أقصى درجة = 5.
        //   مهم: المقارنة مستقلة لكل موقع (مو سلسلة متتالية)،
        //   فلو فرق في موقع 2 ما يلغي تطابق موقع 3 أو الأخير.
        func matchScore(_ candidate: FamilyMember) -> Int {
            let cChain = candidate.fullName
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .map(normalize)
            guard !cChain.isEmpty, !normalizedRequesterChain.isEmpty else { return 0 }

            var score = 0
            // أول 4 مواقع (كل موقع مستقل)
            for i in 0..<4 {
                guard i < normalizedRequesterChain.count, i < cChain.count else { break }
                if normalizedRequesterChain[i] == cChain[i] { score += 1 }
            }
            // الأخير (العائلة) — نقطة إضافية فقط إذا الـ last خارج أول 4
            // (الاسم 5 أجزاء أو أكثر، عشان ما يُحسب مرتين)
            if normalizedRequesterChain.count > 4, cChain.count > 4,
               let rLast = normalizedRequesterChain.last,
               let cLast = cChain.last,
               rLast == cLast {
                score += 1
            }
            return score
        }

        // 7) فلتر متدرّج بناءً على أعلى تطابق متاح:
        //    لو فيه شخص يطابق 3+ من المواقع نعرض من وصلوا لأعلى درجة فقط.
        //    لو ضعيف، نعرض الأفضل المتاح بدل ما القائمة تطلع فاضية.
        let topScore = matches.map(matchScore).max() ?? 0
        let effectiveMin: Int = {
            if topScore >= 3 { return topScore }
            if topScore >= 1 { return topScore }
            return 0
        }()

        // 8) فلترة: على الأقل موقع واحد متطابق
        let candidates = matches.filter { matchScore($0) >= max(1, effectiveMin) }

        // 9) ترتيب الأنسب أول:
        //    1) درجة المواقع الأعلى أولاً (يطابق 5 أنسب من 3)
        //    2) نفس fatherId (لو ربط فعلي موجود)
        //    3) الأعضاء النشطين قبل pending
        //    4) ترتيب السيرفر كـ tiebreaker
        let sorted = candidates.enumerated().sorted { a, b in
            let aScore = matchScore(a.element)
            let bScore = matchScore(b.element)
            if aScore != bScore { return aScore > bScore }

            let reqFatherId = requester?.fatherId
            let aMatchesFather = reqFatherId != nil && a.element.fatherId == reqFatherId
            let bMatchesFather = reqFatherId != nil && b.element.fatherId == reqFatherId
            if aMatchesFather != bMatchesFather { return aMatchesFather }

            let aActive = a.element.role != .pending
            let bActive = b.element.role != .pending
            if aActive != bActive { return aActive }

            return a.offset < b.offset
        }.map(\.element)

        // سقف 8 احتراز للأسماء الشائعة
        joinMatchCandidates = Array(sorted.prefix(8))
        Log.info("[JoinMatch] fullName='\(fullName)', chain=\(requesterChain.prefix(5).joined(separator: " ")) — قبل=\(matches.count), topScore=\(topScore)/5, effectiveMin=\(effectiveMin), بعد=\(candidates.count), نهائي=\(joinMatchCandidates.count)")
    }

    /// استدعاء RPC السيرفر search_members_by_name v2 — exact word + 75% threshold + top-4 parts
    private func fetchServerMatches(fullName: String, excluding excludeId: UUID?) async -> [UUID] {
        struct MatchRow: Decodable {
            let memberId: UUID
            let fullName: String
            let matchScore: Int64
            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
                case fullName = "full_name"
                case matchScore = "match_score"
            }
        }

        do {
            let results: [MatchRow] = try await SupabaseConfig.client
                .rpc("search_members_by_name", params: ["p_query": AnyEncodable(fullName)])
                .execute()
                .value
            let ids = results.compactMap { row -> UUID? in
                row.memberId == excludeId ? nil : row.memberId
            }
            Log.info("[JoinMatch] السيرفر رجّع \(ids.count) مطابقة لـ '\(fullName)'")
            return ids
        } catch {
            Log.warning("[JoinMatch] فشل استدعاء search_members_by_name: \(error.localizedDescription)")
            return []
        }
    }

    /// قسم التطابقات المحتملة — يُلف داخل joinMatchesCard كي يصير كارد مستقل
    /// يظهر دائماً للأدمن على طلبات الانضمام مع loading / empty / list states
    @ViewBuilder
    private func joinMatchesSection(
        candidates: [FamilyMember],
        requesterId: UUID,
        iconInfo: NotificationKindStyle,
        isLoading: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // الترويسة القابلة للنقر — تطوي/تفتح (معطلة عند 0 + loaded عشان empty state يظهر مباشرة)
            Button {
                guard !candidates.isEmpty else { return } // لا توسيع لو فاضي
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(DS.Anim.snappy) {
                    joinMatchesExpanded.toggle()
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(DS.Font.scaled(10, weight: .bold))
                        Text(L10n.t("تطابقات محتملة", "Possible Matches"))
                            .font(DS.Font.scaled(10, weight: .bold))
                    }
                    .foregroundColor(iconInfo.color)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(iconInfo.color.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(iconInfo.color.opacity(0.20), lineWidth: 0.5))

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(DS.Color.textTertiary)
                        } else {
                            Text("\(candidates.count)")
                                .font(DS.Font.scaled(11, weight: .bold))
                                .foregroundColor(DS.Color.textSecondary)

                            if !candidates.isEmpty {
                                Image(systemName: joinMatchesExpanded ? "chevron.up" : "chevron.down")
                                    .font(DS.Font.scaled(11, weight: .bold))
                                    .foregroundColor(DS.Color.textTertiary)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(candidates.isEmpty || isLoading)

            // States: loading | empty | list
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.85)
                        .tint(iconInfo.color)
                    Text(L10n.t("جاري البحث عن مطابقات...", "Searching for matches..."))
                        .font(DS.Font.scaled(11, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                    Spacer()
                }
                .padding(.vertical, DS.Spacing.xs)
            } else if candidates.isEmpty {
                // Empty state — يظهر دائماً (بدون توسيع) لأن المعلومة مهمة
                HStack(spacing: 6) {
                    Image(systemName: "person.fill.questionmark")
                        .font(DS.Font.scaled(12, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                    Text(L10n.t(
                        "لا توجد مطابقات في الشجرة — قد يكون عضو جديد",
                        "No matches found in the tree — may be a new member"
                    ))
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.xs)
                .padding(.horizontal, DS.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.textTertiary.opacity(0.05))
                )
            } else if joinMatchesExpanded {
                VStack(spacing: 6) {
                    ForEach(candidates) { candidate in
                        joinMatchRow(candidate: candidate, requesterId: requesterId)
                    }
                }
            }
        }
    }

    private func joinMatchRow(candidate: FamilyMember, requesterId: UUID) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(DS.Color.textTertiary.opacity(0.08))
                    .frame(width: 28, height: 28)
                if let url = candidate.avatarUrl, !url.isEmpty {
                    CachedAsyncImage(url: URL(string: url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(DS.Font.scaled(11, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }

            Text(chainFourNames(candidate))
                .font(DS.Font.scaled(12, weight: .semibold))
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // زر ربط/دمج — يفتح alert تأكيد قبل الدمج (لا يربط مباشرة)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                guard let nid = selectedNotification?.id else { return }
                linkConfirmTarget = LinkConfirmation(
                    notificationId: nid,
                    requesterId: requesterId,
                    candidate: candidate
                )
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "link")
                        .font(DS.Font.scaled(9, weight: .bold))
                    Text(L10n.t("ربط", "Link"))
                        .font(DS.Font.scaled(10, weight: .bold))
                }
                .foregroundColor(DS.Color.secondary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(DS.Color.secondary.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(DS.Color.secondary.opacity(0.25), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    /// زر دائري مع اسم سفلي — يتبع تصميم DS (مزيج surface + لون + stroke خفيف)
    private func detailCircleAction(icon: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(color)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(color.opacity(0.12))
                    )
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.25), lineWidth: 1)
                    )
            }
            .buttonStyle(DSScaleButtonStyle())

            Text(label)
                .font(DS.Font.scaled(11, weight: .semibold))
                .foregroundColor(DS.Color.textSecondary)
        }
    }

    private func detailActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(14, weight: .semibold))
                Text(label)
                    .font(DS.Font.calloutBold)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .background(color.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(color.opacity(0.20), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Detail Info Row

    private func detailInfoRow(icon: String, label: String, value: some StringProtocol, color: Color) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .semibold))
                .foregroundColor(color)
                .frame(width: NotifLayout.infoIconWidth, alignment: .center)

            Text(label)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: 80, alignment: .leading)

            Text(value)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(DS.Color.textTertiary.opacity(0.1))
            .frame(height: 0.5)
            .padding(.leading, DS.Spacing.lg + NotifLayout.infoIconWidth + DS.Spacing.md)
    }

    // MARK: - Helpers

    private func cleanBody(_ body: String) -> String {
        body.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("بواسطة:") }
            .joined(separator: "\n")
    }

    /// يحذف اسم المدير المنفّذ من بداية نص الإشعار في التفاصيل
    /// (لأنه ظاهر ككبسولة فوق — لا حاجة لتكراره في النص)
    private func bodyWithoutCreatorPrefix(_ body: String, creator: FamilyMember?) -> String {
        let cleaned = cleanBody(body)
        guard let creator else { return cleaned }

        let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
        let candidates = [
            creator.firstName,
            creator.shortFullName,
            fourPartName(creator),
            creator.fullName
        ]

        for name in candidates {
            let n = name.trimmingCharacters(in: .whitespaces)
            guard !n.isEmpty else { continue }
            if trimmed.hasPrefix(n) {
                // احذف الاسم + المسافة اللي بعده
                let after = trimmed.dropFirst(n.count).trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        return cleaned
    }

    /// Renders body text, wrapping «name» delimiters in styled capsules.
    /// Supports \n for hard line breaks (each line becomes its own row).
    @ViewBuilder
    private func richBodyView(_ body: String, font: Font, color: Color, lineLimit: Int? = nil) -> some View {
        let cleaned = cleanBody(body)
        let lines = cleaned.components(separatedBy: "\n")

        if lines.count > 1 {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(lines.indices, id: \.self) { idx in
                    let line = lines[idx]
                    let segs = BodySegment.parse(line)
                    if segs.contains(where: \.isCapsule) {
                        WrappingHStack(segments: segs, font: font, color: color, lineLimit: lineLimit)
                    } else {
                        Text(line)
                            .font(font)
                            .foregroundColor(color)
                            .lineLimit(lineLimit)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        } else {
            let segments = BodySegment.parse(cleaned)
            if segments.contains(where: \.isCapsule) {
                WrappingHStack(segments: segments, font: font, color: color, lineLimit: lineLimit)
            } else {
                Text(cleaned)
                    .font(font)
                    .foregroundColor(color)
                    .lineLimit(lineLimit)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    struct BodySegment: Identifiable {
        let id = UUID()
        let text: String
        let isCapsule: Bool

        /// Splits text on «name» delimiters into plain and capsule segments.
        static func parse(_ text: String) -> [BodySegment] {
            var segments: [BodySegment] = []
            var remaining = text[...]

            while let open = remaining.range(of: "«") {
                let before = remaining[remaining.startIndex..<open.lowerBound]
                if !before.isEmpty { segments.append(.init(text: String(before), isCapsule: false)) }

                let afterOpen = remaining[open.upperBound...]
                guard let close = afterOpen.range(of: "»") else {
                    // No closing delimiter -- treat the rest as plain text
                    segments.append(.init(text: String(remaining[open.lowerBound...]), isCapsule: false))
                    return segments
                }
                let name = afterOpen[afterOpen.startIndex..<close.lowerBound]
                if !name.isEmpty { segments.append(.init(text: String(name), isCapsule: true)) }
                remaining = afterOpen[close.upperBound...]
            }

            if !remaining.isEmpty { segments.append(.init(text: String(remaining), isCapsule: false)) }
            return segments
        }
    }

}

// MARK: - Wrapping HStack for capsule names

private struct WrappingHStack: View {
    let segments: [NotificationsCenterView.BodySegment]
    let font: Font
    let color: Color
    let lineLimit: Int?

    /// يحدد لون الكبسولة حسب محتواها — للأدوار فقط (الأسماء ما لها كبسولة)
    private func roleColor(for text: String) -> Color? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case "مدير", "Admin":       return FamilyMember.UserRole.admin.color
        case "مشرف", "Supervisor":  return FamilyMember.UserRole.supervisor.color
        case "مراقب", "Monitor":    return FamilyMember.UserRole.monitor.color
        case "عضو", "Member":       return FamilyMember.UserRole.member.color
        default:                     return nil
        }
    }

    var body: some View {
        // الأدوار تبقى في كبسولات ملوّنة، الأسماء bold بدون كبسولة
        FlowLayout(spacing: 4) {
            ForEach(segments) { segment in
                if segment.isCapsule, let capColor = roleColor(for: segment.text) {
                    // كبسولة للأدوار فقط
                    Text(segment.text)
                        .font(font).bold()
                        .foregroundColor(capColor)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(capColor.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(capColor.opacity(0.25), lineWidth: 0.5))
                } else if segment.isCapsule {
                    // اسم شخص — bold يلتف على سطرين لو طويل
                    Text(segment.text)
                        .font(font).bold()
                        .foregroundColor(color)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 3)
                } else {
                    Text(segment.text)
                        .font(font)
                        .foregroundColor(color)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 3)
                }
            }
        }
    }
}

// MARK: - Flow Layout (wrapping horizontal layout)
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    /// يحسب حجم subview — لو طوله الطبيعي يتجاوز maxWidth، يجبره يلتف بـ proposal محدود
    private func subviewSize(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let natural = subview.sizeThatFits(.unspecified)
        if natural.width > maxWidth && maxWidth.isFinite {
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        return natural
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subviewSize(subview, maxWidth: maxWidth)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentY += lineHeight + spacing
                currentX = 0
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subviewSize(subview, maxWidth: maxWidth)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentY += lineHeight + spacing
                currentX = bounds.minX
                lineHeight = 0
            }
            // لو subview طويل بطبيعته، نمرر له width محدود ليلتف داخلياً
            let natural = subview.sizeThatFits(.unspecified)
            let placeProposal: ProposedViewSize = (natural.width > maxWidth && maxWidth.isFinite)
                ? ProposedViewSize(width: maxWidth, height: nil)
                : ProposedViewSize(width: size.width, height: size.height)
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: placeProposal)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
