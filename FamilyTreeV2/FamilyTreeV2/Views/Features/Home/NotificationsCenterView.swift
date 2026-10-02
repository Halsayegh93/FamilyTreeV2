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
        "women_add":         .init(icon: "figure.dress.line.vertical.figure",      gradient: DS.Color.gradientPrimary, color: DS.Color.female,      labelAr: "إضافة بشجرة النساء", labelEn: "Women Add"),
        "women_edit":        .init(icon: "square.and.pencil",                       gradient: DS.Color.gradientPrimary, color: DS.Color.female,      labelAr: "تعديل بشجرة النساء", labelEn: "Women Edit"),
        "women_delete":      .init(icon: "trash",                                   gradient: DS.Color.gradientPrimary, color: DS.Color.error,       labelAr: "حذف من شجرة النساء", labelEn: "Women Delete"),
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

    /// إعلان وفاة: بثّ «admin_broadcast» يحمل `details.type` — يُعرض بشكل الوفاة
    /// الهادئ بدل «إعلان من الإدارة»
    private static let deathAnnouncement = NotificationKindStyle(
        icon: "heart.fill", gradient: DS.Color.gradientAccent, color: DS.Color.newsDeath,
        labelAr: "وفاة", labelEn: "Obituary"
    )

    static func style(for notification: AppNotification) -> NotificationKindStyle {
        notification.isDeathAnnouncement ? deathAnnouncement : style(for: notification.kind)
    }

    /// لون رأس مربّع التفاصيل — درجات غامقة تبقى الكتابة البيضاء واضحة عليها في
    /// الوضعين (ألوان الأنواع نفسها تفتح في الداكن): الحذف/الرفض أحمر، الذهبي
    /// ذهبي غامق، الأخضر أخضر غامق، الوفاة رمادي، والباقي كحلي
    static func headerTint(for notification: AppNotification) -> Color {
        notification.isDeathAnnouncement ? DS.Color.textSecondary : headerTint(for: notification.kind)
    }

    static func headerTint(for kind: String) -> Color {
        if kind == "deceased_report" { return DS.Color.textSecondary }
        let c = style(for: kind).color
        if c == DS.Color.error { return DS.Color.error }
        if c == DS.Color.accent { return DS.Color.composerLibrary }
        if c == DS.Color.secondary || c == DS.Color.success { return DS.Color.composerProject }
        return DS.Color.actionNavy
    }
}

// MARK: - Layout Constants

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الوضع الأفقي — نضغط المسافات العمودية حتى لا يُقتص المحتوى
    private var isLandscape: Bool { vSizeClass == .compact }
    /// تعليقات وإعجابات المحظورين لا تظهر في الإشعارات (Guideline 1.2)
    @ObservedObject private var blockedStore = BlockedMembersStore.shared

    @AppStorage("notif_comments") private var notifComments: Bool = true
    @AppStorage("notif_likes") private var notifLikes: Bool = true
    @AppStorage("notif_profile_updates") private var notifProfileUpdates: Bool = true

    @State private var appeared = false
    @State private var isSelecting = false
    @State private var selectedIds: Set<UUID> = []
    @State private var selectedNotification: AppNotification? = nil
    /// نشر تحديث تطبيق من تبويب «المستجدات» (للإدارة)
    @State private var showingAppUpdateComposer = false
    /// العضو المختار لفتح تفاصيله من داخل الإشعار (مثل الشجرة).
    @State private var selectedMember: FamilyMember? = nil
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

    enum NotifTab: Hashable {
        case notifications // إشعاراتي — ما يخصّني شخصياً
        case activity      // المستجدات — تحديثات التطبيق والإعلانات العامة
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

    // MARK: - الهيدر — بهوية الرئيسية

    private var notificationsHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                // الرجوع مكان أيقونة الصفحة (طلب المالك) — بلا علامة ×
                Button { dismiss() } label: {
                    Image(systemName: L10n.isArabic ? "chevron.right" : "chevron.left")
                        .font(DS.Font.scaled(19, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 48, height: 48)
                        .dsHeaderGlassCircle()
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel(L10n.t("رجوع", "Back"))

                Text(L10n.t("الإشعارات", "Notifications"))
                    .font(DS.Font.plex(19, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)

            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.sm)
            .frame(minHeight: 70, alignment: .bottom)

            // شريط سدو زخرفي
            HStack(spacing: 5) {
                Rectangle()
                    .fill(DS.Color.textOnPrimary.opacity(0.16))
                    .frame(height: 1)
                ForEach(0..<5, id: \.self) { i in
                    Rectangle()
                        .fill(DS.Color.textOnPrimary.opacity(i == 2 ? 0.55 : 0.30))
                        .frame(width: i == 2 ? 6 : 4, height: i == 2 ? 6 : 4)
                        .rotationEffect(.degrees(45))
                }
                Rectangle()
                    .fill(DS.Color.textOnPrimary.opacity(0.16))
                    .frame(height: 1)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                DS.Color.gradientPrimary
                // نفس طبقة MainHeaderView — بدونها يطلع الهيدر أفتح
                DS.Color.headerVeil
            }
            .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                notificationsHeader

                // صفحتان — إشعاراتي + المستجدات (تحديثات وإعلانات) للجميع
                do {
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
                    SysStateCard(icon: "bell.fill",
                                 title: L10n.t("جاري التحميل...", "Loading..."),
                                 tint: DS.Color.primary,
                                 isLoading: true)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.top, DS.Spacing.md)
                        .dsStaggerIn(0)   // بطاقة الحالة تصعد وتظهر (تلاشٍ فقط مع «تقليل الحركة»)
                    Spacer(minLength: 0)
                } else if filteredNotifications.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    notificationsList
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // تفاصيل الإشعار مربّع بمنتصف الشاشة لا ورقة سفلية (طلب المالك) — للعرض فقط،
        // فيُغلق أيضاً بالضغط خارجه (بدل سحب الورقة للأسفل سابقاً)
        .dsCenterBox(item: $selectedNotification,
                     onBackgroundTap: { selectedNotification = nil }) { notification in
            notificationDetailSheet(notification)
        }
        .sheet(isPresented: $showingAppUpdateComposer) {
            NavigationStack { AdminAppUpdateView() }
                .presentationDragIndicator(.visible)
        }
        .dsAlert(
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
            Button(L10n.t("حسناً", "OK")) {
                adminRequestVM.mergeResult = nil
            }
        } message: { result in
            switch result {
            case .success(let msg), .failure(let msg):
                Text(msg)
            }
        }
    }

    // MARK: - Action Bar — صف أزرار مرتّب: كلها بنفس الارتفاع والشكل وبعرض متساوٍ (طلب المالك)

    private enum BarStyle {
        case tinted(Color)   // خلفية فاتحة بلون الزر
        case filled          // كحلي الإجراء الأساسي
        case danger          // أحمر (حذف)
    }

    private var actionBar: some View {
        let unreadCount = filteredNotifications.filter { !$0.read }.count
        let canPublish = selectedTab == .activity && authVM.canSendNotifications && !isSelecting
        let showSelect = !isSelecting && !filteredNotifications.isEmpty
        let showReadAll = !isSelecting && unreadCount > 0
        let hasButtons = isSelecting || canPublish || showSelect || showReadAll

        return Group {
            if hasButtons {
                HStack(spacing: DS.Spacing.sm) {
                    // «المستجدات» هي قناة تحديثات التطبيق — والإدارة تنشر منها مباشرة
                    if canPublish {
                        barButton(icon: "megaphone.fill", label: L10n.t("نشر تحديث", "Publish Update"),
                                  style: .filled) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            showingAppUpdateComposer = true
                        }
                    }

                    if isSelecting {
                        // ── وضع التحديد ──
                        barButton(icon: "xmark", label: L10n.t("إلغاء", "Cancel"),
                                  style: .tinted(DS.Color.error)) {
                            withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
                                isSelecting = false
                                selectedIds.removeAll()
                            }
                        }

                        // تحديد الكل / إلغاء الكل
                        let allIds = Set(filteredNotifications.map(\.id))
                        let allSelected = !allIds.isEmpty && selectedIds == allIds
                        barButton(icon: allSelected ? "checkmark.square.fill" : "square.dashed",
                                  label: allSelected ? L10n.t("إلغاء الكل", "Deselect") : L10n.t("الكل", "All"),
                                  style: .tinted(DS.Color.accent)) {
                            withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
                                selectedIds = allSelected ? [] : allIds
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }

                        // مقروء (بعدد المحدد)
                        barButton(icon: "envelope.open.fill",
                                  label: selectedIds.isEmpty ? L10n.t("مقروء", "Read")
                                                             : L10n.t("مقروء (\(selectedIds.count))", "Read (\(selectedIds.count))"),
                                  style: .filled, disabled: selectedIds.isEmpty) {
                            let ids = selectedIds
                            withAnimation(reduceMotion ? nil : DS.Anim.snappy) { selectedIds.removeAll(); isSelecting = false }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            Task { await notificationVM.markNotificationsAsRead(ids: ids) }
                        }

                        // حذف — المدير والمالك فقط
                        if authVM.isAdmin {
                            barButton(icon: "trash.fill", label: L10n.t("حذف", "Delete"),
                                      style: .danger, disabled: selectedIds.isEmpty) {
                                let ids = selectedIds
                                withAnimation(reduceMotion ? nil : DS.Anim.snappy) { selectedIds.removeAll(); isSelecting = false }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                Task { await notificationVM.deleteNotifications(ids: ids) }
                            }
                        }
                    } else {
                        // ── الوضع العادي ──
                        if showSelect {
                            barButton(icon: "checklist.unchecked", label: L10n.t("تحديد", "Select"),
                                      style: .tinted(DS.Color.accent)) {
                                withAnimation(reduceMotion ? nil : DS.Anim.snappy) { isSelecting = true; selectedIds.removeAll() }
                                UISelectionFeedbackGenerator().selectionChanged()
                            }
                        }

                        // قراءة الكل — وعدد غير المقروء داخله بدل شارة منفصلة
                        if showReadAll {
                            barButton(icon: "envelope.open.fill",
                                      label: L10n.t("قراءة الكل (\(unreadCount))", "Read All (\(unreadCount))"),
                                      style: .tinted(DS.Color.primary)) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                Task { await notificationVM.markAllNotificationsAsRead() }
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.xs)
                .animation(reduceMotion ? nil : DS.Anim.snappy, value: isSelecting)
                .animation(reduceMotion ? nil : DS.Anim.snappy, value: selectedIds.count)
            }
        }
    }

    /// زر الشريط: ارتفاع ٤٠ وعرض متساوٍ مع جيرانه، أيقونة + نص، بأحد ثلاثة أشكال
    private func barButton(icon: String, label: String, style: BarStyle,
                           disabled: Bool = false, action: @escaping () -> Void) -> some View {
        let fg: Color
        let bg: AnyShapeStyle
        switch style {
        case .tinted(let tint):
            fg = tint.dsReadableGlyph
            bg = AnyShapeStyle(tint.dsReadableGlyph.opacity(0.12))
        case .filled:
            fg = DSActionFill.label(enabled: !disabled)
            bg = AnyShapeStyle(DSActionFill.style(enabled: !disabled))
        case .danger:
            fg = .white
            bg = AnyShapeStyle(DS.Color.error.opacity(disabled ? 0.45 : 1))
        }
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .bold))
                    .accessibilityHidden(true)
                Text(label)
                    .font(DS.Font.plex(13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule().fill(bg))   // دائري الأطراف (طلب المالك)
            .padding(.vertical, 2)            // مساحة ضغط ٤٤
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .disabled(disabled)
    }

    // MARK: - Filtered Notifications

    private var hiddenKinds: Set<String> {
        var kinds = Set<String>()
        if !notifComments { kinds.insert("news_comment") }
        if !notifLikes { kinds.insert("news_like") }
        if !notifProfileUpdates { kinds.insert("profile_update") }
        return kinds
    }

    // MARK: - التبويبان — المبدّل الكبير المرتّب (DSSegmentedSwitch)

    private func segmentedTabBar(notifCount: Int, activityCount: Int) -> some View {
        DSSegmentedSwitch(
            options: [
                DSSegmentOption(id: NotifTab.notifications,
                                title: L10n.t("الإشعارات", "Notifications"),
                                icon: "bell.badge.fill", count: notifCount),
                DSSegmentOption(id: NotifTab.activity,
                                title: L10n.t("المستجدات", "Activity"),
                                icon: "sparkles", count: activityCount)
            ],
            selection: $selectedTab
        )
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
        NotificationKind.galleryApproved.rawValue,
        NotificationKind.galleryRejected.rawValue,
        // نشر محتوى
        NotificationKind.newsPublished.rawValue,
        // حذف محتوى (إجراء منفّذ — مو طلب معلّق)
        "news_deleted",
    ]

    /// كل الإشعارات بعد تطبيق فلتر الإعدادات (الأنواع المخفية)
    private var visibleNotifications: [AppNotification] {
        let all = notificationVM.notifications.filter { !isFromBlockedMember($0) }
        guard !hiddenKinds.isEmpty else { return all }
        return all.filter { !hiddenKinds.contains($0.kind) }
    }

    /// تعليق أو إعجاب من عضو حظره المستخدم — لا يظهر (طلبات الإدارة لا تتأثر)
    private func isFromBlockedMember(_ n: AppNotification) -> Bool {
        blockedStore.hidesNotification(kind: n.kind, createdBy: n.createdBy, body: n.body)
    }

    /// تاب "إشعاراتي":
    /// - الطلبات اللي تنتظر موافقتي (للأدمن)
    /// - الإشعارات الموجّهة لي شخصياً (ليست إجراءً تمّ على آخرين)
    /// - الإشعارات اليتيمة (kind غير معروف وغير موجّهة لشخص محدد) — كانت
    ///   تختفي قبل، الآن تظهر هنا عشان المستخدم يقدر يقرأها/يحذفها
    private func belongsToNotificationsTab(_ n: AppNotification) -> Bool {
        guard let myId = authVM.currentUser?.id else { return false }

        // «المستجدات» لها تبويبها المستقل
        if belongsToActivityTab(n) { return false }

        let isPendingApproval = Self.pendingApprovalKinds.contains(n.kind)
        let isCompletedAction = Self.completedActionKinds.contains(n.kind)
        let titleIndicatesCompleted = n.title.hasPrefix("تم قبول")
            || n.title.hasPrefix("تم رفض")
            || n.title.contains("Approved")
            || n.title.contains("Rejected")

        // إشعاراتي = ما يخصّني أنا: وضع طلباتي، وأي تغيير على بياناتي.
        // طلبات الآخرين وحركات الإدارة شغل إداري — مكانها أقسام الإدارة
        // وسجل النشاط، لا هنا (طلب المالك).
        if isPendingApproval || isCompletedAction || titleIndicatesCompleted {
            if n.createdBy == myId { return false }   // أنا من نفّذها
            return n.subjectMemberId == myId          // تخصّني شخصياً فقط
        }

        // إشعار موجّه لي (نتيجة طلبي، رسالة إدارية، ترحيب…)
        if n.targetMemberId == myId { return true }

        // إشعار يتيم بلا هدف — يظهر للجميع
        return n.targetMemberId == nil
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
        NotificationKind.diwaniyaPending.rawValue,
        NotificationKind.projectPending.rawValue,
        NotificationKind.newsAdd.rawValue,
        NotificationKind.contactMessage.rawValue,
    ]

    /// تاب «المستجدات»: إعلانات الإدارة وتحديثات التطبيق فقط.
    /// (تنبيهات مثل «فلان نشر منشوراً» هي حركة إدارية ومكانها «سجل النشاط»
    /// في لوحة الإدارة — طلب المالك)
    /// «المستجدات» = ما يخصّ التطبيق نفسه: إصدار جديد، ميزة، صيانة، تنويه.
    /// أي رسالة موجّهة للأعضاء (بث إداري) مكانها «إشعاراتي» — فهي تخصّ العضو
    /// لا التطبيق (طلب المالك).
    private func belongsToActivityTab(_ n: AppNotification) -> Bool {
        n.kind == "app_update"
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

    /// ترتيب دخول القائمة (نمط الأخبار والديوانيات): عنوان كل يوم ثم صفوفه، بالترتيب الظاهر —
    /// رقم أول عنصر (العنوان) في كل قسم؛ `dsCardCascade` يدرّج أول ٧ فقط والباقي مع السابع
    private func cascadeStarts(_ groups: [(String, [AppNotification])]) -> [String: Int] {
        var starts: [String: Int] = [:]
        var next = 0
        for (section, items) in groups {
            starts[section] = next
            next += items.count + 1
        }
        return starts
    }

    private var notificationsList: some View {
        let groups = groupedNotifications
        let starts = cascadeStarts(groups)
        return List {
            ForEach(groups, id: \.0) { section, items in
                let start = starts[section] ?? 0
                Section {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let iconInfo = NotificationKindStyle.style(for: item)
                        let isUnread = !item.read

                        notificationRow(item: item, iconInfo: iconInfo, isUnread: isUnread)
                            // نمط الأخبار والديوانيات: تصعد وتظهر واحدة بعد الأخرى مرة عند الظهور
                            // («تقليل الحركة»: تلاشٍ فقط) — والصفوف التي تُبنى بالتمرير تظهر مباشرة
                            .dsCardCascade(start + 1 + index, appeared: appeared)
                            .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 4, trailing: DS.Spacing.lg))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                // كل عضو يحذف نسخته الخاصة من الإشعار
                                Button(role: .destructive) {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    Task { await notificationVM.deleteNotification(id: item.id) }
                                } label: {
                                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
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
                            .dsFieldFont(12.5, weight: .bold)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text("\(items.count)")
                            .font(DS.Font.plex(11, weight: .bold))
                            .foregroundColor(DS.Color.textTertiary)
                            .monospacedDigit()
                        Rectangle()
                            .fill(DS.Color.textTertiary.opacity(0.18))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 3)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    // عنوان اليوم يدخل قبل صفوفه مباشرة
                    .dsCardCascade(start, appeared: appeared)
                    .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.lg, bottom: 2, trailing: DS.Spacing.lg))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await notificationVM.fetchNotifications(force: true)
        }
        // مرة واحدة حين تظهر القائمة (بعد التحميل إن لم تكن محمّلة) — نفس الأخبار والديوانيات؛
        // بعد أول تخطيط (خلايا `List` تُبنى فيه) حتى تبدأ أول الصفوف مخفية ثم تصعد
        .onAppear { DispatchQueue.main.async { appeared = true } }
    }

    // MARK: - Notification Row (صف موحّد: أيقونة النوع + العنوان والوقت + النص + شارات)

    private func notificationRow(item: AppNotification, iconInfo: NotificationKindStyle, isUnread: Bool) -> some View {
        let isSelected = selectedIds.contains(item.id)
        return Button {
            if isSelecting {
                withAnimation(reduceMotion ? nil : DS.Anim.snappy) {
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
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                // دائرة التحديد في وضع التحديد
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.textTertiary)
                        .frame(width: 26)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                }

                // أيقونة النوع (بلونه لغير المقروء) + نقطة غير مقروء على طرفها
                DSFieldIcon(name: iconInfo.icon, tint: isUnread ? iconInfo.color : DS.Color.textTertiary)
                    .overlay(alignment: .topLeading) {
                        if isUnread && !isSelecting {
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(DS.Color.surface, lineWidth: 2))
                                .offset(x: -3, y: -3)
                        }
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    // العنوان + الوقت
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
                        Text(item.title)
                            .dsFieldFont(13.5, weight: isUnread ? .bold : .semibold)
                            .foregroundColor(isUnread ? DS.Color.fieldLabel : DS.Color.fieldValue)
                            .lineLimit(2)
                        Spacer(minLength: DS.Spacing.xs)
                        Text(relativeTime(item.createdDate))
                            .font(DS.Font.plex(11, weight: .semibold))
                            .foregroundColor(isUnread ? DS.Color.primary : DS.Color.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }

                    // النص
                    richBodyView(
                        item.body,
                        font: DS.Font.plex(12.5),
                        color: isUnread ? DS.Color.fieldValue : DS.Color.textTertiary,
                        lineLimit: 3
                    )

                    // التصنيف + (للإدارة) من أرسل
                    HStack(spacing: DS.Spacing.xs) {
                        SysStatusChip(text: iconInfo.label,
                                      tint: isUnread ? iconInfo.color : DS.Color.textTertiary)

                        if authVM.isAdmin, let creatorId = item.createdBy {
                            let isAdminNotif = Self.completedActionKinds.contains(item.kind)
                            let creator = memberVM.member(byId: creatorId)
                            // في القائمة: «الإدارة» كاسم مُعمَّم لإشعارات تعديل المدير
                            // (الاسم الفعلي يظهر فقط داخل مربّع التفاصيل، للمدراء فقط)
                            let creatorName = isAdminNotif
                                ? L10n.t("الإدارة", "Admin")
                                : (creator?.shortFullName ?? L10n.t("الإدارة", "Admin"))
                            let roleColor: Color = isAdminNotif ? DS.Color.primary : (creator?.roleColor ?? DS.Color.accent)
                            SysStatusChip(text: isAdminNotif ? creatorName : L10n.t("من \(creatorName)", "from \(creatorName)"),
                                          icon: isAdminNotif ? "shield.fill" : "person.fill",
                                          tint: roleColor)
                        }

                        Spacer(minLength: 0)
                        // أزرار الموافقة/الرفض السريعة أُزيلت من صف الإشعار —
                        // الإجراءات تتم من مربّع تفاصيل الإشعار أو من لوحة الإدارة.
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.sm + 2)
            .padding(.vertical, DS.Spacing.sm + 2)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .strokeBorder(isSelected
                              ? DS.Color.primary.opacity(0.75)
                              : (isUnread ? iconInfo.color.dsReadableGlyph.opacity(0.35)
                                          : DS.Color.textTertiary.opacity(0.12)),
                              lineWidth: isSelected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isUnread ? L10n.t("غير مقروء", "Unread") : "")
        .contextMenu {
            if isUnread {
                Button {
                    Task { await notificationVM.markNotificationAsRead(id: item.id) }
                } label: {
                    Label(L10n.t("تعليم كمقروء", "Mark as Read"), systemImage: "envelope.open")
                }
            }
            Button(role: .destructive) {
                Task { await notificationVM.deleteNotification(id: item.id) }
            } label: {
                Label(L10n.t("حذف", "Delete"), systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        let isActivity = authVM.isAdmin && selectedTab == .activity
        return VStack {
            SysStateCard(
                icon: isActivity ? "sparkles" : "bell.slash.fill",
                title: isActivity
                    ? L10n.t("لا يوجد نشاط", "No Activity")
                    : L10n.t("لا توجد إشعارات", "No Notifications"),
                hint: isActivity
                    ? L10n.t("نشاط النظام يظهر هنا", "System activity appears here")
                    : L10n.t("الإشعارات الموجهة لك تظهر هنا", "Notifications for you appear here"),
                tint: DS.Color.primary
            )
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.md)
            .dsStaggerIn(0)   // بطاقة الحالة تصعد وتظهر (تلاشٍ فقط مع «تقليل الحركة»)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Detail Box (مربّع تفاصيل الإشعار بمنتصف الشاشة — طلب المالك)

    /// تفاصيل إشعار واحد بنفس مربّعات التطبيق: رأس بلون نوع الإشعار، أقسام،
    /// وشريط سفلي — «تعليم كمقروء» كحلي يمين (لغير المقروء) و«إغلاق» يسار.
    /// للقراءة فقط كما كان: الموافقة والرفض والمراجعة من أقسام الإدارة المختصّة،
    /// والحذف من قائمة الإشعار في القائمة (طلب المالك).
    private func notificationDetailSheet(_ notification: AppNotification) -> some View {
        let iconInfo = NotificationKindStyle.style(for: notification)

        return DSComposer(
            title: iconInfo.label,
            subtitle: relativeTime(notification.createdDate),
            icon: iconInfo.icon,
            tint: NotificationKindStyle.headerTint(for: notification),
            actionTitle: L10n.t("تعليم كمقروء", "Mark as Read"),
            actionIcon: "envelope.open",
            showsAction: !notification.read,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: !notification.read,
            onSubmit: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let id = notification.id
                selectedNotification = nil
                Task { await notificationVM.markNotificationAsRead(id: id) }
            },
            onCancel: { selectedNotification = nil }
        ) {
            detailBoxSections(notification, iconInfo: iconInfo)
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
        .dsAlert(
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
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// أقسام المربّع بنفس ترتيب الشيت السابق: العضو ← التطابقات ← الإشعار ← ما تغيّر
    @ViewBuilder
    private func detailBoxSections(_ notification: AppNotification, iconInfo: NotificationKindStyle) -> some View {
        let relatedMember = relatedMemberForNotification(notification)
        let isJoinRequest = notification.kind == RequestType.joinRequest.rawValue
            || notification.kind == NotificationKind.linkRequest.rawValue
        // قسم التطابقات المحتملة — قبل نص الإشعار للأهمية
        // ملاحظة: الإشعارات اللي من trigger تحفظ pending ID في created_by،
        // والإشعارات من admin_requests تحفظه في request_id — نستخدم fallback
        let showMatchesSection = isJoinRequest && authVM.canModerate
        let matchesRequesterId: UUID? = showMatchesSection
            ? (notification.requestId ?? notification.createdBy) : nil
        // الأقسام تدخل تباعاً (0، 1، 2…) حسب الظاهر منها
        let matchesIndex = relatedMember == nil ? 0 : 1
        let bodyIndex = matchesIndex + (matchesRequesterId == nil ? 0 : 1)

        if let member = relatedMember {
            DSComposerSection(title: L10n.t("العضو", "Member"),
                              icon: "person.fill",
                              tint: DS.Color.primary,
                              index: 0) {
                detailMemberCard(member: member)
            }
        }

        if let requesterId = matchesRequesterId {
            joinMatchesCard(
                candidates: joinMatchCandidates,
                requesterId: requesterId,
                iconInfo: iconInfo,
                isLoading: !joinMatchesLoaded,
                index: matchesIndex
            )
        }

        detailBodyCard(notification: notification, iconInfo: iconInfo, index: bodyIndex)

        if authVM.isAdmin,
           let details = notification.details,
           !details.changes.isEmpty {
            detailChangesSection(details, index: bodyIndex + 1)
        }
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

    // MARK: - Detail: Member Row (صورة + اسم + دور) — يفتح تفاصيل العضو
    private func detailMemberCard(member: FamilyMember) -> some View {
        Button {
            selectedMember = member
        } label: {
            detailMemberCardBody(member: member)
        }
        .buttonStyle(DSScaleButtonStyle())
        .fullScreenCover(item: $selectedMember) { m in
            MemberDetailsView(member: m, centered: true)
                .background(ClearPresentationBackground())
        }
        .transaction { t in
            // يظهر المربّع في مكانه بلا انزلاق — والإغلاق بلا انزلاق يتم داخل المربّع
            if selectedMember != nil { t.disablesAnimations = true }
        }
    }

    private func detailMemberCardBody(member: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // صورة العضو (دائرية) بحلقة بلون دوره
            ZStack {
                Circle()
                    .fill(DS.Color.textTertiary.opacity(0.08))

                if let url = member.avatarUrl, !url.isEmpty {
                    CachedAsyncImage(url: URL(string: url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(Circle().stroke(member.roleColor.opacity(0.35), lineWidth: 1.5).padding(-2))
            .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

            VStack(alignment: .leading, spacing: 3) {
                Text(fourPartName(member))
                    .dsFieldFont(14.5, weight: .bold)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // رقاقة الدور
                Text(member.roleName)
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(member.roleColor)
                    .padding(.horizontal, DS.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(member.roleColor.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 0)

            // سهم — إشارة أن الصف يفتح تفاصيل العضو
            Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
        .contentShape(Rectangle())
    }

    // MARK: - Detail: Body Section (نص الإشعار)
    private func detailBodyCard(
        notification: AppNotification,
        iconInfo: NotificationKindStyle,
        index: Int
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
        // المحتوى الأساسي — للإعلانات الإدارية يُعرض بشكل بارز (نص أكبر)
        // لأن الرسالة نفسها هي محتوى الإشعار.
        let isBroadcast = (notification.kind == "admin" || notification.kind == "admin_broadcast")
        let bodyText = bodyWithoutCreatorPrefix(notification.body, creator: actualCreator)

        return DSComposerSection(
            title: L10n.t("الإشعار", "Notification"),
            icon: "text.bubble.fill",
            tint: iconInfo.color,
            index: index
        ) {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text(notification.title)
                    .font(DS.Font.plex(15.5, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // chip التصنيف + chip الإدارة / المدير المنفّذ + الحالة
                detailChipsRow(notification: notification, iconInfo: iconInfo,
                               isAdminSender: isAdminSender, creator: actualCreator)

                // معاينة "قبل → بعد" — تظهر فقط للإشعارات اللي تحمل تفاصيل تغيير
                if let firstChange = notification.details?.changes.first {
                    detailFromToInline(change: firstChange, color: iconInfo.color)
                }

                if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    richBodyView(
                        bodyText,
                        font: DS.Font.plex(isBroadcast ? 16.5 : 14.5, weight: isBroadcast ? .semibold : .regular),
                        color: DS.Color.textPrimary
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()

            // التاريخ والوقت الكامل
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "calendar", tint: DS.Color.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("التاريخ", "Date"))
                        .dsFieldFont(12, weight: .heavy)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(fullDateTime(date))
                        .dsFieldFont(14)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)   // «التاريخ، …» عنصراً واحداً
        }
    }

    /// chip التصنيف + chip «الإدارة» أو المدير المنفّذ (للأدمن) + حالة القراءة
    private func detailChipsRow(
        notification: AppNotification,
        iconInfo: NotificationKindStyle,
        isAdminSender: Bool,
        creator: FamilyMember?
    ) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            // chip التصنيف
            HStack(spacing: 4) {
                Image(systemName: iconInfo.icon)
                    .font(.system(size: 10.5, weight: .bold))
                    .accessibilityHidden(true)
                Text(iconInfo.label)
                    .font(DS.Font.plex(11, weight: .bold))
            }
            .foregroundColor(iconInfo.color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 3)
            .background(iconInfo.color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(iconInfo.color.opacity(0.20), lineWidth: 0.5))

            // chip «الإدارة» — لإشعارات الإدارة المُرسَلة (بدون اسم شخصي)
            if isAdminSender {
                HStack(spacing: 3) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 10.5, weight: .bold))
                        .accessibilityHidden(true)
                    Text(L10n.t("الإدارة", "Admin"))
                        .font(DS.Font.plex(11, weight: .bold))
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(DS.Color.primary.opacity(0.10), in: Capsule())
                .overlay(Capsule().stroke(DS.Color.primary.opacity(0.20), lineWidth: 0.5))
            }

            // chip المدير المنفّذ — للأدمن فقط، اسم حقيقي مو "الإدارة"
            if let creator {
                HStack(spacing: 3) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .accessibilityHidden(true)
                    Text(creator.shortFullName)
                        .font(DS.Font.plex(11, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundColor(creator.roleColor)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, 3)
                .background(creator.roleColor.opacity(0.10), in: Capsule())
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
                    .font(DS.Font.plex(11, weight: .bold))
                    .foregroundColor(notification.read ? DS.Color.textTertiary : DS.Color.primary)
            }
        }
    }

    // MARK: - Detail: Matches Section (قسم التطابقات المحتملة)

    /// العنوان يطوي/يفتح القائمة (مطويّة افتراضياً) — لا طيّ أثناء البحث أو بلا
    /// نتائج، فتظهر حالة البحث أو «لا توجد مطابقات» مباشرة
    private func joinMatchesCard(
        candidates: [FamilyMember],
        requesterId: UUID,
        iconInfo: NotificationKindStyle,
        isLoading: Bool,
        index: Int
    ) -> some View {
        let collapsible = !isLoading && !candidates.isEmpty
        let expanded = Binding<Bool>(
            get: { joinMatchesExpanded },
            set: { newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                joinMatchesExpanded = newValue
            }
        )
        return DSComposerSection(
            title: L10n.t("تطابقات محتملة", "Possible Matches"),
            icon: "person.2.fill",
            tint: iconInfo.color,
            trailing: isLoading ? nil : "\(candidates.count)",
            index: index,
            isOpen: collapsible ? expanded : nil
        ) {
            joinMatchesSection(
                candidates: candidates,
                requesterId: requesterId,
                iconInfo: iconInfo,
                isLoading: isLoading
            )
        }
    }

    /// معاينة "قبل → بعد" مدمجة — تظهر داخل كرت التفاصيل لإشعارات admin_edit_*
    @ViewBuilder
    private func detailFromToInline(change: AppNotification.NotificationDetails.ChangeEntry, color: Color) -> some View {
        let isOpaque = AppNotification.NotificationDetails.isOpaqueField(change.field)
        let fieldLabel = AppNotification.NotificationDetails.localizedFieldName(change.field)

        HStack(spacing: 6) {
            // اسم الحقل
            Text(fieldLabel)
                .font(DS.Font.plex(11.5, weight: .bold))
                .foregroundColor(DS.Color.textSecondary)

            Text("·")
                .font(DS.Font.plex(11.5, weight: .bold))
                .foregroundColor(DS.Color.textTertiary)

            if isOpaque {
                // للحقول التي لا تُعرض قيمتها (مثل الصورة): "تم التحديث"
                Text(L10n.t("تم التحديث", "Updated"))
                    .font(DS.Font.plex(11.5, weight: .medium))
                    .foregroundColor(DS.Color.textSecondary)
            } else {
                // قيمة قبل
                Text(change.before ?? "—")
                    .font(DS.Font.plex(11.5, weight: .medium))
                    .foregroundColor(DS.Color.error.opacity(0.85))
                    .strikethrough()
                    .lineLimit(1)

                // سهم
                Image(systemName: L10n.isArabic ? "arrow.left" : "arrow.right")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(DS.Color.textTertiary)

                // قيمة بعد
                Text(change.after ?? "—")
                    .font(DS.Font.plex(11.5, weight: .bold))
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
        // الشطب والسهم لا يُسمعان — القارئ الصوتي يقرأ «الحقل: قبل … بعد …» سطراً واحداً
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOpaque
            ? "\(fieldLabel): " + L10n.t("تم التحديث", "Updated")
            : L10n.t("\(fieldLabel): قبل \(change.before ?? "—")، بعد \(change.after ?? "—")",
                     "\(fieldLabel): before \(change.before ?? "—"), after \(change.after ?? "—")"))
    }

    private func detailChip(text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(DS.Font.scaled(11, weight: .bold))
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

    // MARK: - Detail: What Changed (محتوى DSChangeDetailsCard نفسه بشكل أقسام المربّعات)

    /// «ما الذي تغيّر» — كل تغيير في صف: اسم الحقل ثم قبل/بعد (أو ملخّص للحقول التي
    /// لا تُعرض قيمتها كالصورة). للأدمن فقط كما كان.
    private func detailChangesSection(_ details: AppNotification.NotificationDetails, index: Int) -> some View {
        DSComposerSection(
            title: L10n.t("ما الذي تغيّر", "What Changed"),
            icon: "pencil.line",
            tint: DS.Color.accent,
            trailing: "\(details.changes.count)",
            index: index
        ) {
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(details.changes.enumerated()), id: \.offset) { _, change in
                    detailChangeRow(change)
                }
            }
        }
    }

    private func detailChangeRow(_ change: AppNotification.NotificationDetails.ChangeEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppNotification.NotificationDetails.localizedFieldName(change.field))
                .dsFieldFont(12, weight: .heavy)
                .foregroundColor(DS.Color.fieldLabel)

            if AppNotification.NotificationDetails.isOpaqueField(change.field) {
                detailChangeLine(label: nil,
                                 value: detailOpaqueChangeLabel(for: change.field),
                                 color: DS.Color.primary)
            } else {
                detailChangeLine(label: L10n.t("قبل:", "Before:"),
                                 value: detailChangeValue(change.before),
                                 color: DS.Color.error.opacity(0.85))
                detailChangeLine(label: L10n.t("بعد:", "After:"),
                                 value: detailChangeValue(change.after),
                                 color: DS.Color.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }

    /// سطر قيمة بخط ملوّن جانبي (قبل أحمر، بعد أخضر)
    private func detailChangeLine(label: String?, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let label {
                Text(label)
                    .font(DS.Font.plex(12, weight: .bold))
                    .foregroundColor(color)
            }
            Text(value)
                .dsFieldFont(13.5)
                .foregroundColor(DS.Color.fieldValue)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.leading, DS.Spacing.sm + 2)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(color.opacity(0.55))
                .frame(width: 2.5)
        }
    }

    /// ملخّص الحقول التي لا تُعرض قيمتها — نفس نصوص DSChangeDetailsCard
    private func detailOpaqueChangeLabel(for field: String) -> String {
        switch field {
        case "avatar_url":
            return L10n.t("تم تحديث الصورة الشخصية", "Profile photo was updated")
        case "father_id":
            return L10n.t("تم تحديث ولي الأمر", "Father reference was updated")
        default:
            return L10n.t("تم التحديث", "Updated")
        }
    }

    private func detailChangeValue(_ raw: String?) -> String {
        guard let v = raw, !v.isEmpty else { return L10n.t("—", "—") }
        return v
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

    /// محتوى قسم التطابقات: جاري البحث | لا توجد مطابقات | القائمة (عند فتح القسم)
    /// يظهر دائماً للأدمن على طلبات الانضمام
    @ViewBuilder
    private func joinMatchesSection(
        candidates: [FamilyMember],
        requesterId: UUID,
        iconInfo: NotificationKindStyle,
        isLoading: Bool = false
    ) -> some View {
        if isLoading {
            HStack(spacing: DS.Spacing.sm) {
                Spacer(minLength: 0)
                ProgressView()
                    .scaleEffect(0.85)
                    .tint(iconInfo.color)
                Text(L10n.t("جاري البحث عن مطابقات...", "Searching for matches..."))
                    .font(DS.Font.plex(12, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                Spacer(minLength: 0)
            }
            .dsRowBox()
        } else if candidates.isEmpty {
            // Empty state — يظهر دائماً (بدون توسيع) لأن المعلومة مهمة
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "person.fill.questionmark", tint: DS.Color.textTertiary)
                    .accessibilityHidden(true)
                Text(L10n.t(
                    "لا توجد مطابقات في الشجرة — قد يكون عضو جديد",
                    "No matches found in the tree — may be a new member"
                ))
                .dsFieldFont(12.5, weight: .medium)
                .foregroundColor(DS.Color.fieldValue)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .dsRowBox()
        } else {
            // القائمة — تظهر عند فتح القسم (القسم المطويّ يخفيها)
            VStack(spacing: DS.Spacing.sm) {
                ForEach(candidates) { candidate in
                    joinMatchRow(candidate: candidate, requesterId: requesterId)
                }
            }
        }
    }

    private func joinMatchRow(candidate: FamilyMember, requesterId: UUID) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            ZStack {
                Circle()
                    .fill(DS.Color.textTertiary.opacity(0.08))
                if let url = candidate.avatarUrl, !url.isEmpty {
                    CachedAsyncImage(url: URL(string: url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.fill")
                            .foregroundColor(DS.Color.textTertiary)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)   // الصورة زخرفة — الاسم يُقرأ بعدها

            Text(chainFourNames(candidate))
                .dsFieldFont(13, weight: .semibold)
                .foregroundColor(DS.Color.fieldLabel)
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
                        .font(.system(size: 10.5, weight: .bold))
                        .accessibilityHidden(true)
                    Text(L10n.t("ربط", "Link"))
                        .font(DS.Font.plex(11.5, weight: .bold))
                }
                .foregroundColor(DS.Color.secondary)
                .padding(.horizontal, DS.Spacing.sm + 2)
                .frame(height: 28)
                .background(DS.Color.secondary.opacity(0.12), in: Capsule())
                .overlay(Capsule().stroke(DS.Color.secondary.opacity(0.25), lineWidth: 0.5))
                // مساحة ضغط ٤٤ (توصية أبل): الكبسولة ٢٨ كما هي، والحشوة السالبة تُبقي ارتفاع الصف
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .padding(.vertical, -8)
            }
            .buttonStyle(DSScaleButtonStyle())
        }
        .dsRowBox()
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
