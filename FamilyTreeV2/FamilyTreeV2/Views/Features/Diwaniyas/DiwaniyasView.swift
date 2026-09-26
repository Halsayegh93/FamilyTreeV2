import SwiftUI

// MARK: - DiwaniyasView
struct DiwaniyasView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @StateObject private var viewModel = DiwaniyasViewModel()
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var showingAddRequest = false
    @State private var diwaniyaToEdit: Diwaniya? = nil
    @State private var diwaniyaToDelete: Diwaniya? = nil
    @State private var diwaniyaToReport: Diwaniya? = nil
    @State private var reportReason = ""
    @State private var reportSent = false
    @State private var appeared = false
    @State private var cachedFilteredDiwaniyas: [Diwaniya] = []
    /// كل الظاهرة قبل فلتر النوع — للعدّاد في الشريط
    @State private var cachedVisibleDiwaniyas: [Diwaniya] = []
    /// ديوانيات / حسينيات (nil = الكل) — قسم الحسينيات (طلب المالك)
    @State private var kindFilter: DiwaniyaKind? = nil
    @Namespace private var filterNS
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — بطاقات على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                VStack(spacing: 0) {
                    MainHeaderView(
                        selectedTab: $selectedTab,
                        showingNotifications: $showingNotifications,
                        title: L10n.t("الديوانيات", "Diwaniyas"),
                        subtitle: L10n.t("ديوانيات وحسينيات · \(cachedVisibleDiwaniyas.count)",
                                         "Diwaniyas & husseiniyas · \(cachedVisibleDiwaniyas.count)"),
                        icon: "map.fill",
                        backgroundGradient: DS.Color.gradientPrimary
                    )

                    kindFilterBar

                    if viewModel.isLoading && filteredDiwaniyas.isEmpty {
                        Spacer()
                        ProgressView(L10n.t("جاري التحميل...", "Loading..."))
                        Spacer()
                    } else if filteredDiwaniyas.isEmpty {
                        emptyStateView
                    } else {
                        ScrollView(showsIndicators: false) {
                            Group {
                                if isLandscape {
                                    // الوضع الأفقي: عمودان من بطاقات الديوانيات
                                    LazyVGrid(
                                        columns: [GridItem(.adaptive(minimum: 340), spacing: DS.Spacing.md, alignment: .top)],
                                        alignment: .center,
                                        spacing: DS.Spacing.md
                                    ) {
                                        ForEach(Array(filteredDiwaniyas.enumerated()), id: \.element.id) { index, diwaniya in
                                            diwaniyaCard(for: diwaniya)
                                                .opacity(appeared ? 1 : 0)
                                                .offset(y: appeared ? 0 : 30)
                                                .animation(DS.Anim.smooth.delay(Double(min(index, 6)) * 0.06), value: appeared)
                                        }
                                    }
                                } else {
                                    LazyVStack(spacing: DS.Spacing.md) {
                                        ForEach(Array(filteredDiwaniyas.enumerated()), id: \.element.id) { index, diwaniya in
                                            diwaniyaCard(for: diwaniya)
                                                .opacity(appeared ? 1 : 0)
                                                .offset(y: appeared ? 0 : 30)
                                                .animation(DS.Anim.smooth.delay(Double(min(index, 6)) * 0.06), value: appeared)
                                        }
                                    }
                                }
                            }
                            .padding(DS.Spacing.lg)
                            .padding(.bottom, DS.Spacing.xxxl)
                            .onAppear {
                                guard !appeared else { return }
                                appeared = true
                            }
                        }
                        .refreshable {
                            await viewModel.fetchDiwaniyas()
                        }
                    }
                }

                // زر الإضافة السفلي (FAB) — مثل بقية الصفحات
                HStack {
                    Spacer()
                    DSFloatingButton(icon: "plus", color: DS.Color.primary) {
                        showingAddRequest = true
                    }
                    .accessibilityLabel(L10n.t("إضافة", "Add"))
                    .padding(.trailing, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .toolbar(.hidden, for: .navigationBar)
            // الإضافة مربّع بمنتصف الشاشة لا ورقة سفلية (طلب المالك)
            .fullScreenCover(isPresented: $showingAddRequest) {
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    AddDiwaniyaRequestView()
                        .environmentObject(viewModel)
                        .environmentObject(authVM)
                }
                .background(ClearPresentationBackground())
            }
            .transaction { t in
                if showingAddRequest { t.disablesAnimations = true }
            }
            // التعديل بنفس مربّع الإضافة بمنتصف الشاشة (طلب المالك)
            .fullScreenCover(item: $diwaniyaToEdit) { diwaniya in
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
                    EditDiwaniyaView(diwaniya: diwaniya)
                        .environmentObject(viewModel)
                        .environmentObject(authVM)
                }
                .background(ClearPresentationBackground())
            }
            .transaction { t in if diwaniyaToEdit != nil { t.disablesAnimations = true } }
            .dsAlert(L10n.t("إبلاغ عن ديوانية", "Report Diwaniya"), isPresented: .init(
                get: { diwaniyaToReport != nil },
                set: { if !$0 { diwaniyaToReport = nil } }
            )) {
                TextField(L10n.t("سبب الإبلاغ (اختياري)", "Reason (optional)"), text: $reportReason)
                Button(L10n.t("إبلاغ", "Report"), role: .destructive) {
                    let target = diwaniyaToReport
                    let reason = reportReason
                    diwaniyaToReport = nil
                    reportReason = ""
                    if let target {
                        Task {
                            let ok = await notificationVM.reportContent(
                                contentKind: L10n.t("ديوانية", "diwaniya"),
                                contentLabel: target.title,
                                contentId: target.id,
                                reason: reason
                            )
                            if ok { await MainActor.run { reportSent = true } }
                        }
                    }
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { diwaniyaToReport = nil; reportReason = "" }
            } message: {
                Text(L10n.t("اكتب سبب الإبلاغ، وسيتم إرساله للإدارة لمراجعة هذه الديوانية.",
                           "Enter a reason; it will be sent to the admins to review this diwaniya."))
            }
            .dsAlert(L10n.t("تم الإبلاغ", "Reported"), isPresented: $reportSent) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t("شكراً لك، وصل بلاغك للإدارة وستتم مراجعته خلال ٢٤ ساعة.", "Thank you — your report reached the admins and will be reviewed within 24 hours."))
            }
            .dsAlert(
                L10n.t("حذف الديوانية", "Delete Diwaniya"),
                isPresented: .init(
                    get: { diwaniyaToDelete != nil },
                    set: { if !$0 { diwaniyaToDelete = nil } }
                )
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                    diwaniyaToDelete = nil
                }
                Button(L10n.t("حذف", "Delete"), role: .destructive) {
                    if let d = diwaniyaToDelete {
                        Task { await viewModel.deleteDiwaniya(id: d.id) }
                        diwaniyaToDelete = nil
                    }
                }
            } message: {
                Text(L10n.t(
                    "هل أنت متأكد من حذف \"\(diwaniyaToDelete?.title ?? "")\"؟",
                    "Are you sure you want to delete \"\(diwaniyaToDelete?.title ?? "")\"?"
                ))
            }
            .task {
                await viewModel.fetchDiwaniyas()
            }
            .onAppear {
                viewModel.canModerate = authVM.canModerate
                viewModel.authVM = authVM
                viewModel.notificationVM = notificationVM
                rebuildFilteredDiwaniyas()
            }
            .onChange(of: viewModel.diwaniyas.count) { _ in rebuildFilteredDiwaniyas() }
            .onChange(of: kindFilter) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { rebuildFilteredDiwaniyas() }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .dsAlert(L10n.t("خطأ", "Error"), isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(L10n.t("إعادة المحاولة", "Retry")) {
                    viewModel.errorMessage = nil
                    Task { await viewModel.fetchDiwaniyas() }
                }
                Button(L10n.t("إغلاق", "Dismiss"), role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }



    // MARK: - Filtered Diwaniyas
    private var filteredDiwaniyas: [Diwaniya] { cachedFilteredDiwaniyas }

    private func rebuildFilteredDiwaniyas() {
        let userId = authVM.currentUser?.id
        let canModerate = authVM.canModerate
        cachedVisibleDiwaniyas = viewModel.diwaniyas.filter { diwaniya in
            if diwaniya.approvalStatus == "approved" { return true }
            if diwaniya.approvalStatus == "pending" {
                return canModerate || diwaniya.ownerId == userId
            }
            return false
        }
        cachedFilteredDiwaniyas = cachedVisibleDiwaniyas.filter { d in
            switch kindFilter {
            case nil: return true
            case .husseiniya?: return d.isHusseiniya
            case .diwaniya?: return !d.isHusseiniya
            }
        }
    }

    // MARK: - شريط الأقسام: الكل / ديوانيات / حسينيات

    private var kindFilterBar: some View {
        HStack(spacing: 6) {
            filterChip(nil, title: L10n.t("الكل", "All"), icon: "square.grid.2x2.fill",
                       count: cachedVisibleDiwaniyas.count, tint: DS.Color.actionNavy)
            ForEach(DiwaniyaKind.allCases) { k in
                filterChip(k, title: k.plural, icon: k.icon,
                           count: cachedVisibleDiwaniyas.filter { k == .husseiniya ? $0.isHusseiniya : !$0.isHusseiniya }.count,
                           tint: k.tint)
            }
        }
        .padding(4)
        .background(Capsule().fill(DS.Color.surface))
        .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.12), lineWidth: 1))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }

    private func filterChip(_ k: DiwaniyaKind?, title: String, icon: String, count: Int, tint: Color) -> some View {
        let selected = kindFilter == k
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { kindFilter = k }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .bold))
                Text(title).font(DS.Font.plex(12.5, weight: .bold)).lineLimit(1)
                Text("\(count)")
                    .font(DS.Font.plex(10.5, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(selected ? Color.white.opacity(0.22) : tint.opacity(0.12)))
            }
            .foregroundColor(selected ? .white : DS.Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                if selected {
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.82)], startPoint: .top, endPoint: .bottom))
                        .matchedGeometryEffect(id: "kind-filter", in: filterNS)
                        .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: DS.Spacing.xl) {
            Spacer()
            ZStack {
                Circle()
                    .fill(DS.Color.gridDiwaniya.opacity(0.10))
                    .frame(width: 120, height: 120)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DS.Color.gridDiwaniya.opacity(0.20),
                                DS.Color.primary.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)

                Image(systemName: "mappin.slash")
                    .font(DS.Font.scaled(40, weight: .bold))
                    .foregroundColor(DS.Color.gridDiwaniya)
            }

            VStack(spacing: DS.Spacing.sm) {
                Text(kindFilter == .husseiniya ? L10n.t("لا توجد حسينيات", "No Husseiniyas Yet")
                                               : L10n.t("لا توجد ديوانيات", "No Diwaniyas Yet"))
                    .font(DS.Font.title3)
                    .fontWeight(.black)
                    .foregroundColor(DS.Color.textPrimary)
                Text(L10n.t(
                    "اضغط + لإضافة ديوانيتك.\nتُعرض بعد موافقة الإدارة.",
                    "Tap + to add your diwaniya.\nIt appears after admin approval."
                ))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            }
            Spacer()
        }
    }

    // MARK: - Diwaniya Card
    private func diwaniyaCard(for item: Diwaniya) -> some View {
        let isClosed = item.isClosed == true
        let isPending = item.approvalStatus == "pending"
        let kindTint = item.isHusseiniya ? DS.Color.composerHusseiniya : DS.Color.gridDiwaniya
        let cardColor = isPending ? DS.Color.warning : (isClosed ? DS.Color.textTertiary : kindTint)

        return DSCard(padding: 0) {
            VStack(spacing: 0) {
                // badge تحت المراجعة
                if isPending {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(DS.Font.scaled(12, weight: .bold))
                        Text(L10n.t("تحت المراجعة", "Under Review"))
                            .font(DS.Font.scaled(12, weight: .bold))
                    }
                    .foregroundColor(DS.Color.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(DS.Color.warning.opacity(0.08))
                }

                // شريط علوي ملون
                HStack(spacing: DS.Spacing.md) {
                    // أيقونة بتدرج
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isPending
                                        ? [DS.Color.warning.opacity(0.2), DS.Color.warning.opacity(0.1)]
                                        : (isClosed
                                            ? [DS.Color.textTertiary.opacity(0.3), DS.Color.textTertiary.opacity(0.1)]
                                            : [kindTint.opacity(0.2), DS.Color.primary.opacity(0.1)]),
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: DS.Icon.size, height: DS.Icon.size)
                        Image(systemName: item.isHusseiniya ? DiwaniyaKind.husseiniya.icon : (item.imageUrl ?? "map.fill"))
                            .font(DS.Font.scaled(22, weight: .bold))
                            .foregroundColor(cardColor)
                    }

                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack(spacing: DS.Spacing.sm) {
                            Text(item.title)
                                .font(DS.Font.headline)
                                .foregroundColor(isPending ? DS.Color.textSecondary : (isClosed ? DS.Color.textTertiary : DS.Color.textPrimary))

                            if item.isHusseiniya {
                                Text(DiwaniyaKind.husseiniya.title)
                                    .font(DS.Font.plex(10.5, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(DS.Color.composerHusseiniya))
                            }

                            if isClosed && !isPending {
                                HStack(spacing: DS.Spacing.xs) {
                                    Image(systemName: "lock.fill")
                                        .font(DS.Font.caption2)
                                    Text(L10n.t("مغلقة", "Closed"))
                                        .font(DS.Font.scaled(11, weight: .bold))
                                }
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, DS.Spacing.xs)
                                .background(DS.Color.error.opacity(0.8))
                                .clipShape(Capsule())
                            }
                        }
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "person.fill")
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textTertiary)
                            Text(item.ownerName)
                                .font(DS.Font.callout)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                    }

                    Spacer()

                    let canManageThis = authVM.canDeleteDiwaniyas || authVM.currentUser?.id == item.ownerId
                    let canReportThis = authVM.currentUser?.id != item.ownerId
                    if canManageThis || canReportThis {
                        Menu {
                            if canManageThis {
                                Button(action: { diwaniyaToEdit = item }) {
                                    Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                                }
                                Button(role: .destructive, action: { diwaniyaToDelete = item }) {
                                    Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                }
                            }
                            // إبلاغ متاح للجميع (أعضاء وإدارة) لغير ديوانياتهم — سياسة Apple
                            if canReportThis {
                                if canManageThis { Divider() }
                                Button(action: { diwaniyaToReport = item }) {
                                    Label(L10n.t("إبلاغ", "Report"), systemImage: "exclamationmark.bubble")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(DS.Font.scaled(16, weight: .bold))
                                .foregroundColor(DS.Color.textSecondary)
                                .frame(width: DS.Icon.sizeSm, height: DS.Icon.sizeSm)
                                .background(DS.Color.textTertiary.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.md)

                // ═══ شرائح المعلومات — أفقية متمرّرة بدل الصفوف الطويلة ═══
                let infoItems = buildDiwaniyaInfoItems(item)
                if !infoItems.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DS.Spacing.sm) {
                            ForEach(Array(infoItems.enumerated()), id: \.offset) { _, info in
                                HStack(spacing: 5) {
                                    Image(systemName: info.icon)
                                        .font(DS.Font.scaled(11, weight: .semibold))
                                        .foregroundColor(info.color)
                                    Text(info.text)
                                        .font(DS.Font.scaled(12, weight: .medium))
                                        .foregroundColor(DS.Color.textSecondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, DS.Spacing.sm + 2)
                                .padding(.vertical, 6)
                                .background(info.color.opacity(0.08), in: Capsule())
                                .overlay(Capsule().strokeBorder(info.color.opacity(0.18), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.md)
                    }
                }

                // ═══ إجراءات أيقونية مدمجة ═══
                let hasLocation = item.mapsUrl?.isEmpty == false
                let hasPhone = item.contactPhone?.isEmpty == false
                if hasLocation || hasPhone {
                    HStack(spacing: DS.Spacing.sm) {
                        if let mapsStr = item.mapsUrl, !mapsStr.isEmpty, let url = URL(string: mapsStr) {
                            Button(action: { UIApplication.shared.open(url) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "location.fill")
                                        .font(DS.Font.scaled(12, weight: .bold))
                                    Text(L10n.t("الموقع", "Location"))
                                        .font(DS.Font.scaled(12, weight: .bold))
                                }
                                .foregroundColor(DS.Color.textOnPrimary)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, 8)
                                .background(DS.Color.gradientPrimary, in: Capsule())
                            }
                            .buttonStyle(DSBoldButtonStyle())
                        }

                        if let phone = item.contactPhone, !phone.isEmpty, let callURL = KuwaitPhone.telURL(phone) {
                            Button(action: { UIApplication.shared.open(callURL) }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "phone.fill")
                                        .font(DS.Font.scaled(12, weight: .bold))
                                    Text(L10n.t("اتصال", "Call"))
                                        .font(DS.Font.scaled(12, weight: .bold))
                                }
                                .foregroundColor(DS.Color.success)
                                .padding(.horizontal, DS.Spacing.md)
                                .padding(.vertical, 8)
                                .background(DS.Color.success.opacity(0.10), in: Capsule())
                                .overlay(Capsule().strokeBorder(DS.Color.success.opacity(0.30), lineWidth: 1))
                            }
                            .buttonStyle(DSBoldButtonStyle())
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.md)
                }
            }
        }
    }
    
    private struct DiwaniyaInfoItem {
        let icon: String
        let color: Color
        let text: String
    }
    
    private func buildDiwaniyaInfoItems(_ item: Diwaniya) -> [DiwaniyaInfoItem] {
        var items: [DiwaniyaInfoItem] = []
        if let schedule = item.scheduleText, !schedule.isEmpty {
            items.append(DiwaniyaInfoItem(icon: "clock.fill", color: DS.Color.warning, text: schedule))
        }
        if let addr = item.address, !addr.isEmpty {
            items.append(DiwaniyaInfoItem(icon: "mappin.and.ellipse", color: DS.Color.accent, text: addr))
        }
        if let phone = item.contactPhone, !phone.isEmpty {
            items.append(DiwaniyaInfoItem(icon: "phone.fill", color: DS.Color.success, text: KuwaitPhone.display(phone)))
        }
        return items
    }
}

// MARK: - Add Diwaniya Request View
/// نموذج الديوانية/الحسينية الموحّد — نفسه للإضافة والتعديل (طلب المالك:
/// تصميم واحد بنفس التنسيق). الحالة (مفتوحة/متوقفة) تظهر في التعديل فقط.
private struct DiwaniyaComposerForm: View {
    @Binding var name: String
    @Binding var ownerName: String
    @Binding var selectedDays: Set<Int>
    @Binding var selectedTimes: Set<String>
    @Binding var phoneNumber: String
    @Binding var selectedPhoneCountry: KuwaitPhone.Country
    @Binding var locationURL: String
    @Binding var address: String
    @Binding var kind: DiwaniyaKind
    var isClosed: Binding<Bool>? = nil
    let isEdit: Bool
    let canAutoApprove: Bool
    let isSubmitting: Bool
    /// إدخال لم يُحفظ (يحسبه صاحب البيانات: الإضافة أو التعديل) — «إلغاء» يسأل قبل التجاهل
    var hasUnsavedChanges: Bool = false
    let onSubmit: () -> Void
    let onCancel: () -> Void
    /// «تقليل الحركة» (توصية أبل): بلا دوران ولا تكبير — اللون وحده يدلّ على الاختيار
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let weekDays: [(id: Int, ar: String, en: String)] = [
        (0, "السبت", "Saturday"), (1, "الأحد", "Sunday"), (2, "الإثنين", "Monday"),
        (3, "الثلاثاء", "Tuesday"), (4, "الأربعاء", "Wednesday"), (5, "الخميس", "Thursday"),
        (6, "الجمعة", "Friday"),
    ]

    private static let timeSlots: [String] = {
        var slots: [String] = []
        for hour in 6...11 {
            slots.append("\(hour):00")
            if hour < 11 { slots.append("\(hour):30") }
        }
        return slots
    }()

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var daysDisplayText: String {
        if selectedDays.count == 7 { return L10n.t("كل يوم", "Every day") }
        return selectedDays.sorted().compactMap { id in
            guard let day = Self.weekDays.first(where: { $0.id == id }) else { return nil }
            return L10n.t("كل \(day.ar)", "Every \(day.en)")
        }.joined(separator: "، ")
    }

    private static func timeToMinutes(_ t: String) -> Int {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0) * 60 + (parts.last ?? 0)
    }

    private var timeDisplayText: String {
        guard !selectedTimes.isEmpty else { return "" }
        let sorted = selectedTimes.sorted { Self.timeToMinutes($0) < Self.timeToMinutes($1) }
        guard let first = sorted.first, let last = sorted.last else { return "" }
        if sorted.count == 1 { return L10n.t("\(first) م", "\(first) PM") }
        return L10n.t("من \(first) إلى \(last) م", "\(first) - \(last) PM")
    }

    private enum Extra: String, Identifiable { case time, phone, location; var id: String { rawValue } }
    @State private var activeExtra: Extra?
    @Namespace private var kindNS

    /// اختصار اليوم للدوائر
    private static let dayLetters = ["س", "ح", "ن", "ث", "ر", "خ", "ج"]


    private var phoneSummary: String? {
        guard !phoneNumber.isEmpty else { return nil }
        return "\(selectedPhoneCountry.dialingCode) \(phoneNumber)"
    }

    private var locationSummary: String? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return locationURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : L10n.t("رابط الخريطة", "Map link")
    }

    var body: some View {
        DSComposer(
            title: isEdit
                ? (kind == .husseiniya ? L10n.t("تعديل الحسينية", "Edit Husseiniya") : L10n.t("تعديل الديوانية", "Edit Diwaniya"))
                : (kind == .husseiniya ? L10n.t("إضافة حسينية", "Add Husseiniya") : L10n.t("إضافة ديوانية", "Add Diwaniya")),
            subtitle: kind == .husseiniya ? L10n.t("مجلس ذكر ومناسبات العائلة", "A place for gatherings and remembrance")
                                          : L10n.t("مجلس يجمع العائلة والأصدقاء", "Where family and friends gather"),
            icon: kind.icon,
            tint: kind.tint,
            actionTitle: isEdit ? L10n.t("حفظ", "Save")
                                : (canAutoApprove ? L10n.t("إضافة", "Add") : L10n.t("إرسال للمراجعة", "Submit")),
            actionIcon: isEdit ? "checkmark" : "plus",
            canSubmit: isFormValid,
            isBusy: isSubmitting,
            note: (isEdit || canAutoApprove) ? nil : L10n.t("تظهر للجميع بعد موافقة الإدارة", "Appears after admin approval"),
            isBehindExtra: activeExtra != nil,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: onSubmit,
            onCancel: onCancel
        ) {
            // ── النوع ──
            DSComposerSection(title: L10n.t("النوع", "Type"), icon: "square.grid.2x2.fill", tint: kind.tint, index: 0) {
                HStack(spacing: 4) {
                    ForEach(DiwaniyaKind.allCases) { k in kindOption(k) }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous).fill(DS.Color.background))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.14), lineWidth: 1))
            }

            // ── البيانات ──
            DSComposerSection(title: L10n.t("البيانات", "Details"), icon: "info.circle.fill", tint: kind.tint, index: 1) {
                DSComposerField(icon: kind.icon,
                                label: kind == .husseiniya ? L10n.t("اسم الحسينية *", "Name *") : L10n.t("اسم الديوانية *", "Name *"),
                                placeholder: kind == .husseiniya ? L10n.t("مثال: حسينية آل محمدعلي", "e.g. …")
                                                                 : L10n.t("مثال: ديوانية أبو صالح", "e.g. …"),
                                text: $name, tint: kind.tint, limit: 100)
                DSComposerField(icon: "person.fill",
                                label: kind == .husseiniya ? L10n.t("القائم عليها *", "Host *") : L10n.t("صاحب الديوانية *", "Owner *"),
                                placeholder: L10n.t("الاسم", "Name"),
                                text: $ownerName, tint: kind.tint, limit: 100)
            }

            // ── المواعيد ──
            DSComposerSection(title: L10n.t("المواعيد", "Schedule"), icon: "calendar", tint: kind.tint,
                              trailing: selectedDays.isEmpty ? L10n.t("اختياري", "Optional") : nil, index: 2) {
                HStack(spacing: 5) {
                    ForEach(Self.weekDays, id: \.id) { day in dayCircle(day.id, name: L10n.t(day.ar, day.en)) }
                }
                if !daysDisplayText.isEmpty {
                    Text(daysDisplayText)
                        .font(DS.Font.plex(11.5, weight: .semibold))
                        .foregroundColor(kind.tint)
                        .transition(.opacity)
                }
                DSExtraChip(icon: "clock.fill", title: L10n.t("الوقت", "Time"), tint: kind.tint,
                            summary: timeDisplayText.isEmpty ? nil : timeDisplayText) { activeExtra = .time }
            }

            // ── إضافات ──
            DSComposerSection(title: L10n.t("إضافات", "Extras"), icon: "plus.circle.fill", tint: kind.tint,
                              trailing: L10n.t("اختياري", "Optional"), index: 3) {
                HStack(spacing: DS.Spacing.sm) {
                    DSExtraChip(icon: "phone.fill", title: L10n.t("رقم التواصل", "Phone"), tint: kind.tint,
                                summary: phoneSummary) { activeExtra = .phone }
                    DSExtraChip(icon: "mappin.and.ellipse", title: L10n.t("الموقع", "Location"), tint: kind.tint,
                                summary: locationSummary) { activeExtra = .location }
                    Spacer(minLength: 0)
                }
            }

            // ── الحالة (التعديل فقط) ──
            if let isClosed {
                DSComposerSection(title: L10n.t("الحالة", "Status"), icon: "power", tint: kind.tint, index: 4) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: isClosed.wrappedValue ? "lock.fill" : "lock.open.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(isClosed.wrappedValue ? DS.Color.error : DS.Color.success)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill((isClosed.wrappedValue ? DS.Color.error : DS.Color.success).opacity(0.12)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(isClosed.wrappedValue ? L10n.t("متوقفة حالياً", "Currently closed")
                                                       : L10n.t("مفتوحة ونشطة", "Open and active"))
                                .font(DS.Font.plex(13.5, weight: .bold))
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("إيقافها يُظهرها «مغلقة» في القائمة", "Closing shows it as closed"))
                                .font(DS.Font.plex(10.5))
                                .foregroundColor(DS.Color.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(get: { !isClosed.wrappedValue },
                                                 set: { isClosed.wrappedValue = !$0 }))
                            .labelsHidden()
                            .tint(DS.Color.success)
                            // المفتاح بلا نص ظاهر — القارئ الصوتي يسمّيه (القيمة: تشغيل/إيقاف)
                            .accessibilityLabel(L10n.t("مفتوحة", "Open"))
                    }
                    .padding(.horizontal, DS.Spacing.sm + 2)
                    .padding(.vertical, DS.Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(DS.Color.textTertiary.opacity(0.15), lineWidth: 1))
                }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: kind)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedDays)
        .dsExtraBox(item: $activeExtra) { extra in
            switch extra {
            case .time: timeBox
            case .phone: phoneBox
            case .location: locationBox
            }
        }
    }

    private func kindOption(_ k: DiwaniyaKind) -> some View {
        let selected = kind == k
        return Button {
            guard kind != k else { return }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.75)) { kind = k }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: k.icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(selected ? .white : k.tint)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(selected ? Color.white.opacity(0.2) : k.tint.opacity(0.12)))
                    .rotationEffect(.degrees(selected || reduceMotion ? 0 : -12))
                    .accessibilityHidden(true)
                Text(k.title)
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(selected ? .white : DS.Color.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(LinearGradient(colors: [k.tint, k.tint.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        .matchedGeometryEffect(id: "kind-pill", in: kindNS)
                        .shadow(color: k.tint.opacity(0.4), radius: 8, y: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func dayCircle(_ id: Int, name: String) -> some View {
        let on = selectedDays.contains(id)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                if on { selectedDays.remove(id) } else { selectedDays.insert(id) }
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(Self.dayLetters[id])
                .font(DS.Font.plex(13.5, weight: .bold))
                .foregroundColor(on ? .white : DS.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Circle().fill(on ? kind.tint : DS.Color.background))
                .overlay(Circle().strokeBorder(on ? Color.clear : DS.Color.textTertiary.opacity(0.2), lineWidth: 1))
                .scaleEffect(on && !reduceMotion ? 1.06 : 1)
                // الدائرة ٣٨ ← مساحة ضغط ٤٤ ارتفاعاً، وعرضاً حتى نصف المسافة (٢٫٥) بين
                // الدوائر فتتلاصق المساحات بلا تداخل — التخطيط كما هو
                .tapArea(top: 3, leading: 2.5, bottom: 3, trailing: 2.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - المربّعات الإضافية

    private var timeBox: some View {
        DSExtraBox(
            title: L10n.t("الوقت", "Time"),
            subtitle: L10n.t("اختر وقت البداية والنهاية", "Pick the start and end"),
            icon: "clock.fill", tint: kind.tint,
            onDone: { dsCloseExtra { activeExtra = nil } },
            onCancel: { dsCloseExtra { activeExtra = nil } }
        ) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.timeSlots, id: \.self) { time in
                    let on = selectedTimes.contains(time)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                            if on { selectedTimes.remove(time) } else { selectedTimes.insert(time) }
                        }
                    } label: {
                        Text(L10n.t("\(time) م", "\(time) PM"))
                            .font(DS.Font.plex(12, weight: on ? .bold : .medium))
                            .foregroundColor(on ? .white : DS.Color.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(on ? kind.tint : DS.Color.surface))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(on ? Color.clear : DS.Color.textTertiary.opacity(0.18), lineWidth: 1))
                            // مساحة الضغط حتى نصف المسافة (٣) بين الخانات من كل جهة — ٤٢ ارتفاعاً
                            // بلا تداخل ولا تغيير في الشبكة (الصفوف متباعدة ٦ فقط)
                            .tapArea(top: 3, leading: 3, bottom: 3, trailing: 3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if !timeDisplayText.isEmpty {
                Text(timeDisplayText)
                    .font(DS.Font.plex(12.5, weight: .bold))
                    .foregroundColor(kind.tint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var phoneBox: some View {
        DSExtraBox(
            title: L10n.t("رقم التواصل", "Contact phone"),
            subtitle: L10n.t("يظهر في بطاقة المجلس للتواصل", "Shown on the card for contact"),
            icon: "phone.fill", tint: kind.tint,
            onDone: { dsCloseExtra { activeExtra = nil } },
            onCancel: { dsCloseExtra { activeExtra = nil } }
        ) {
            DSPhoneField(country: $selectedPhoneCountry, digits: $phoneNumber,
                         placeholder: L10n.t("رقم الهاتف", "Phone number"), compact: true, bordered: true)
            if !phoneNumber.isEmpty {
                Button { phoneNumber = "" } label: {
                    Label(L10n.t("إزالة الرقم", "Remove"), systemImage: "trash")
                        .font(DS.Font.plex(12, weight: .semibold))
                        .foregroundColor(DS.Color.error)
                        // النص ١٨ ← مساحة ضغط ٤٤: حشوة ١ (+٢ للتخطيط فقط) ثم ١٢ فوق وتحت حتى
                        // حقل الرقم والأزرار بلا تغطيتهما
                        .padding(.vertical, 1)
                        .tapArea(top: 12, leading: 0, bottom: 12, trailing: 0)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var locationBox: some View {
        DSExtraBox(
            title: L10n.t("الموقع", "Location"),
            subtitle: L10n.t("المنطقة ورابط الخريطة", "Area and a map link"),
            icon: "mappin.and.ellipse", tint: kind.tint,
            onDone: { dsCloseExtra { activeExtra = nil } },
            onCancel: { dsCloseExtra { activeExtra = nil } }
        ) {
            DSComposerField(icon: "mappin.and.ellipse", label: L10n.t("المنطقة / العنوان", "Area / address"),
                            placeholder: L10n.t("مثال: المنصورية", "e.g. Mansouriya"),
                            text: $address, tint: kind.tint, limit: 120)
            DSComposerField(icon: "link", label: L10n.t("رابط الخريطة", "Map link"),
                            placeholder: "https://maps…", text: $locationURL, tint: kind.tint,
                            keyboard: .URL, ltr: true)
        }
    }

}

private struct AddDiwaniyaRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: DiwaniyasViewModel
    @EnvironmentObject var authVM: AuthViewModel

    @State private var name = ""
    @State private var ownerName = ""
    @State private var selectedDays: Set<Int> = []
    @State private var selectedTimes: Set<String> = []
    @State private var daysOpen = false
    @State private var timesOpen = false
    @State private var phoneNumber = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var locationURL = ""
    @State private var address = ""
    @State private var isSubmitting = false
    @State private var showError = false

    private static let weekDays: [(id: Int, ar: String, en: String)] = [
        (0, "السبت", "Saturday"),
        (1, "الأحد", "Sunday"),
        (2, "الإثنين", "Monday"),
        (3, "الثلاثاء", "Tuesday"),
        (4, "الأربعاء", "Wednesday"),
        (5, "الخميس", "Thursday"),
        (6, "الجمعة", "Friday"),
    ]

    private static let timeSlots: [String] = {
        var slots: [String] = []
        for hour in 6...11 {
            slots.append("\(hour):00")
            if hour < 11 { slots.append("\(hour):30") }
        }
        return slots
    }()

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var daysDisplayText: String {
        if selectedDays.count == 7 { return L10n.t("كل يوم", "Every day") }
        let sorted = selectedDays.sorted()
        return sorted.compactMap { id in
            guard let day = Self.weekDays.first(where: { $0.id == id }) else { return nil }
            return L10n.t("كل \(day.ar)", "Every \(day.en)")
        }.joined(separator: "، ")
    }

    private static func timeToMinutes(_ t: String) -> Int {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0) * 60 + (parts.last ?? 0)
    }

    private var timeDisplayText: String {
        guard !selectedTimes.isEmpty else { return "" }
        let sorted: [String] = selectedTimes.sorted { Self.timeToMinutes($0) < Self.timeToMinutes($1) }
        guard let first = sorted.first, let last = sorted.last else { return "" }
        if sorted.count == 1 {
            return L10n.t("\(first) م", "\(first) PM")
        }
        return L10n.t("من \(first) إلى \(last) م", "\(first) - \(last) PM")
    }

    private var scheduleText: String {
        let daysText = daysDisplayText
        if daysText.isEmpty { return "" }
        let timeText = timeDisplayText
        if timeText.isEmpty { return daysText }
        return "\(daysText) - \(timeText)"
    }

    @State private var kind: DiwaniyaKind = .diwaniya

    private var canAutoApprove: Bool {
        authVM.currentUser?.role == .owner || authVM.currentUser?.role == .admin
    }

    /// ما أدخله المستخدم ولم يُرسل (نص، أيام، وقت، رقم، موقع) — «إلغاء» يسأل قبل التجاهل
    /// (توصية أبل). «النوع» (ديوانية/حسينية) اختيار فقط فلا يُحتسب.
    private var hasUnsavedChanges: Bool {
        [name, ownerName, address, locationURL]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !selectedDays.isEmpty || !selectedTimes.isEmpty || !phoneNumber.isEmpty
    }

    var body: some View {
        DiwaniyaComposerForm(
            name: $name, ownerName: $ownerName,
            selectedDays: $selectedDays, selectedTimes: $selectedTimes,
            phoneNumber: $phoneNumber, selectedPhoneCountry: $selectedPhoneCountry,
            locationURL: $locationURL, address: $address, kind: $kind,
            isEdit: false,
            canAutoApprove: canAutoApprove,
            isSubmitting: isSubmitting,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { Task { await submitDiwaniya() } },
            onCancel: { dismiss() }
        )
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showError) {} message: {
            Text(viewModel.errorMessage ?? L10n.t("فشل الإضافة", "Failed to add."))
        }
    }

    // MARK: - بطاقة وهيدر مصغّران

    private func compactCard<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(DS.Color.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.textTertiary.opacity(0.10), lineWidth: 1)
            )
            .dsSubtleShadow()
    }

    private func compactHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(DS.Font.scaled(11, weight: .bold))
                .foregroundColor(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.top, DS.Spacing.sm + 2)
        .padding(.bottom, DS.Spacing.xs)
    }

    private func submitDiwaniya() async {
        guard let user = authVM.currentUser, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedURL = locationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let composedPhone = phoneNumber.isEmpty
            ? ""
            : (KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber) ?? "")
        // الاعتماد للمالك والمدير فقط (جدول الصلاحيات) — غيرهم ينتظر الموافقة
        let canAutoApprove = user.role == .owner || user.role == .admin
        let success = await viewModel.addDiwaniya(
            ownerId: user.id,
            ownerName: ownerName,
            title: name,
            scheduleText: selectedDays.isEmpty ? nil : scheduleText,
            scheduleDays: Array(selectedDays),
            contactPhone: composedPhone,
            mapsUrl: trimmedURL.isEmpty ? nil : trimmedURL,
            address: trimmedAddress.isEmpty ? nil : trimmedAddress,
            kind: kind,
            autoApprove: canAutoApprove
        )
        if success { dismiss() } else { showError = true }
    }

    private func formField(
        icon: String, iconColors: [Color], placeholder: String,
        text: Binding<String>, keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSIcon(icon, color: iconColors.first ?? DS.Color.primary, size: 30, iconSize: 13)
            TextField(placeholder, text: text)
                .font(DS.Font.scaled(13))
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .autocorrectionDisabled(keyboard == .URL || keyboard == .phonePad)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 5)
    }
}

// MARK: - Edit Diwaniya View
private struct EditDiwaniyaView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var viewModel: DiwaniyasViewModel
    @EnvironmentObject var authVM: AuthViewModel

    let diwaniya: Diwaniya

    @State private var name: String
    @State private var ownerName: String
    @State private var selectedDays: Set<Int>
    @State private var selectedTimes: Set<String>
    @State private var daysOpen = false
    @State private var timesOpen = false
    @State private var phoneNumber: String
    @State private var selectedPhoneCountry: KuwaitPhone.Country
    @State private var locationURL: String
    @State private var address: String
    @State private var isClosed: Bool
    @State private var kind: DiwaniyaKind
    @State private var isSubmitting = false
    @State private var showError = false

    private static let weekDays: [(id: Int, ar: String, en: String)] = [
        (0, "السبت", "Saturday"),
        (1, "الأحد", "Sunday"),
        (2, "الإثنين", "Monday"),
        (3, "الثلاثاء", "Tuesday"),
        (4, "الأربعاء", "Wednesday"),
        (5, "الخميس", "Thursday"),
        (6, "الجمعة", "Friday"),
    ]

    private static let timeSlots: [String] = {
        var slots: [String] = []
        for hour in 6...11 {
            slots.append("\(hour):00")
            if hour < 11 { slots.append("\(hour):30") }
        }
        return slots
    }()

    init(diwaniya: Diwaniya) {
        self.diwaniya = diwaniya
        _name = State(initialValue: diwaniya.title)
        _ownerName = State(initialValue: diwaniya.ownerName)
        let detectedPhone = KuwaitPhone.detectCountryAndLocal(diwaniya.contactPhone)
        _selectedPhoneCountry = State(initialValue: detectedPhone.country)
        _phoneNumber = State(initialValue: detectedPhone.localDigits)
        _locationURL = State(initialValue: diwaniya.mapsUrl ?? "")
        _address = State(initialValue: diwaniya.address ?? "")
        _kind = State(initialValue: diwaniya.isHusseiniya ? .husseiniya : .diwaniya)
        _isClosed = State(initialValue: diwaniya.isClosed ?? false)

        // Parse existing schedule text back into selectedDays + selectedTimes
        var days = Set<Int>()
        var parsedTimes = Set<String>()
        if let schedule = diwaniya.scheduleText {
            let allDays: [(id: Int, ar: String, en: String)] = [
                (0, "السبت", "Saturday"), (1, "الأحد", "Sunday"),
                (2, "الإثنين", "Monday"), (3, "الثلاثاء", "Tuesday"),
                (4, "الأربعاء", "Wednesday"), (5, "الخميس", "Thursday"),
                (6, "الجمعة", "Friday"),
            ]
            for day in allDays {
                if schedule.contains(day.ar) || schedule.contains(day.en) {
                    days.insert(day.id)
                }
            }
            // Extract times
            let timePattern = try? NSRegularExpression(pattern: #"(\d{1,2}:\d{2})"#)
            if let matches = timePattern?.matches(in: schedule, range: NSRange(schedule.startIndex..., in: schedule)) {
                for match in matches {
                    if let range = Range(match.range(at: 1), in: schedule) {
                        parsedTimes.insert(String(schedule[range]))
                    }
                }
            }
        }
        _selectedDays = State(initialValue: days)
        _selectedTimes = State(initialValue: parsedTimes)

        _initial = State(initialValue: Fields(
            name: diwaniya.title, ownerName: diwaniya.ownerName,
            days: days, times: parsedTimes,
            phoneDigits: detectedPhone.localDigits, phoneCountry: detectedPhone.country,
            locationURL: diwaniya.mapsUrl ?? "", address: diwaniya.address ?? "",
            kind: diwaniya.isHusseiniya ? .husseiniya : .diwaniya,
            isClosed: diwaniya.isClosed ?? false).normalized)
    }

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    private struct Fields: Equatable {
        var name, ownerName: String
        var days: Set<Int>
        var times: Set<String>
        var phoneDigits: String
        var phoneCountry: KuwaitPhone.Country?
        var locationURL, address: String
        var kind: DiwaniyaKind
        var isClosed: Bool

        /// بلا فراغات الأطراف، ودولة الرقم لا تُحتسب إن لم يوجد رقم
        var normalized: Fields {
            let t: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return Fields(name: t(name), ownerName: t(ownerName), days: days, times: times,
                          phoneDigits: phoneDigits, phoneCountry: phoneDigits.isEmpty ? nil : phoneCountry,
                          locationURL: t(locationURL), address: t(address), kind: kind, isClosed: isClosed)
        }
    }

    /// القيم التي فُتح بها المربّع — تُلتقط مرة واحدة
    @State private var initial: Fields

    /// أي حقل يختلف عمّا فُتح به المربّع — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        Fields(name: name, ownerName: ownerName, days: selectedDays, times: selectedTimes,
               phoneDigits: phoneNumber, phoneCountry: selectedPhoneCountry,
               locationURL: locationURL, address: address, kind: kind, isClosed: isClosed).normalized
            != initial
    }

    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var daysDisplayText: String {
        if selectedDays.count == 7 { return L10n.t("كل يوم", "Every day") }
        let sorted = selectedDays.sorted()
        return sorted.compactMap { id in
            guard let day = Self.weekDays.first(where: { $0.id == id }) else { return nil }
            return L10n.t("كل \(day.ar)", "Every \(day.en)")
        }.joined(separator: "، ")
    }

    private static func timeToMinutes(_ t: String) -> Int {
        let parts = t.split(separator: ":").compactMap { Int($0) }
        return (parts.first ?? 0) * 60 + (parts.last ?? 0)
    }

    private var timeDisplayText: String {
        guard !selectedTimes.isEmpty else { return "" }
        let sorted: [String] = selectedTimes.sorted { Self.timeToMinutes($0) < Self.timeToMinutes($1) }
        guard let first = sorted.first, let last = sorted.last else { return "" }
        if sorted.count == 1 {
            return L10n.t("\(first) م", "\(first) PM")
        }
        return L10n.t("من \(first) إلى \(last) م", "\(first) - \(last) PM")
    }

    private var scheduleText: String {
        let daysText = daysDisplayText
        if daysText.isEmpty { return "" }
        let timeText = timeDisplayText
        if timeText.isEmpty { return daysText }
        return "\(daysText) - \(timeText)"
    }

    var body: some View {
        DiwaniyaComposerForm(
            name: $name, ownerName: $ownerName,
            selectedDays: $selectedDays, selectedTimes: $selectedTimes,
            phoneNumber: $phoneNumber, selectedPhoneCountry: $selectedPhoneCountry,
            locationURL: $locationURL, address: $address, kind: $kind,
            isClosed: $isClosed,
            isEdit: true,
            canAutoApprove: true,
            isSubmitting: isSubmitting,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { Task { await saveChanges() } },
            onCancel: { dismiss() }
        )
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showError) {} message: {
            Text(viewModel.errorMessage ?? L10n.t("فشل تحديث الديوانية", "Failed to update diwaniya."))
        }
    }

    private func saveChanges() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let trimmedURL = locationURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let composedPhone = phoneNumber.isEmpty
            ? nil
            : KuwaitPhone.normalizedForStorage(country: selectedPhoneCountry, rawLocalDigits: phoneNumber)
        let success = await viewModel.updateDiwaniya(
            id: diwaniya.id,
            title: name,
            ownerName: ownerName,
            scheduleText: selectedDays.isEmpty ? nil : scheduleText,
            scheduleDays: Array(selectedDays),
            contactPhone: composedPhone,
            mapsUrl: trimmedURL.isEmpty ? nil : trimmedURL,
            address: trimmedAddress.isEmpty ? nil : trimmedAddress,
            isClosed: isClosed,
            kind: kind
        )
        if success { dismiss() } else { showError = true }
    }

    private func formField(
        icon: String, iconColors: [Color], placeholder: String,
        text: Binding<String>, keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIcon(icon, color: iconColors.first ?? DS.Color.primary)
            TextField(placeholder, text: text)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.leading)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .URL ? .never : .words)
                .autocorrectionDisabled(keyboard == .URL || keyboard == .phonePad)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }
}

// MARK: - مساحة ضغط أكبر (توصية أبل: ٤٤ نقطة)

private extension View {
    /// يكبّر منطقة اللمس حول عنصر صغير بلا تغيير في شكله ولا في التخطيط: الحشوة تُضاف
    /// لمنطقة اللمس ثم تُسترد من التخطيط. القيم محسوبة لكل عنصر حتى لا تتداخل مع جيرانه.
    func tapArea(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        self
            .padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing))
    }
}
