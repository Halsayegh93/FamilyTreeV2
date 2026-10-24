import SwiftUI

// MARK: - DiwaniyasView
/// صفحة الديوانيات — «أسبوع المجالس» (طلب المالك ٢٠٢٦-١٠-٢٤ «ابي ترتيب جديد للديوانيات»): بطاقة الأسبوع
/// ثم المجالس مرتّبة بالأقرب (`DiwaniyaBoard` + `DiwaniyaOrganizer`). بلا شريط «ديوانيات/حسينيات» (طلب المالك
/// «شيل شريط الديوانيات والحسينيات») — النوع وسم صغير على بطاقة الحسينية، ويُختار في مربّع الإضافة والتعديل.
struct DiwaniyasView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var viewModel = DiwaniyasViewModel()
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @State private var showingAddRequest = false
    @State private var diwaniyaToEdit: Diwaniya? = nil
    @State private var diwaniyaToDelete: Diwaniya? = nil
    @State private var diwaniyaToReport: Diwaniya? = nil
    /// رفض طلب معلّق من القسم نفسه — بتأكيد (يُحذف الطلب ويصل لصاحبه إشعار)
    @State private var diwaniyaToReject: Diwaniya? = nil
    @State private var reportReason = ""
    @State private var reportSent = false
    /// الظاهرة للمستخدم: المعتمدة، والمعلّقة للإدارة ولصاحبها
    @State private var cachedVisibleDiwaniyas: [Diwaniya] = []

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
                        icon: AppSection.diwaniyas.symbol,   // «مجلس»
                        section: .diwaniyas
                    )

                    if viewModel.isLoading && cachedVisibleDiwaniyas.isEmpty {
                        // التحميل الموحّد: مجسّم «المجلس» يتنفّس (بدل الدوّارة)
                        DSPageLoader(section: .diwaniyas)
                    } else if cachedVisibleDiwaniyas.isEmpty {
                        emptyStateView
                    } else {
                        // «أسبوع المجالس» — حدّ `AnyView` يفصل جسم القائمة عن جسم الصفحة (عمق المكدس على الآيفون)
                        AnyView(DiwaniyaBoard(items: cachedVisibleDiwaniyas, actions: cardActions,
                                              onRefresh: { await viewModel.fetchDiwaniyas() }))
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
                    .dsAlertField()   // حقل لا زرّ: الزرّان جنب بعض
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
            // رفض المعلّقة من القسم — نفس رفض «طلبات المراجعة» (يُحذف الطلب ويُشعَر صاحبه)
            .dsAlert(
                L10n.t("رفض الديوانية", "Reject Diwaniya"),
                isPresented: .init(
                    get: { diwaniyaToReject != nil },
                    set: { if !$0 { diwaniyaToReject = nil } }
                )
            ) {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { diwaniyaToReject = nil }
                Button(L10n.t("رفض", "Reject"), role: .destructive) {
                    if let d = diwaniyaToReject {
                        Task { await viewModel.rejectFromSection(d) }
                    }
                    diwaniyaToReject = nil
                }
            } message: {
                Text(L10n.t(
                    "لن تُعرض «\(diwaniyaToReject?.title ?? "")» ويصل لصاحبها إشعار بعدم اعتمادها.",
                    "«\(diwaniyaToReject?.title ?? "")» won't be shown, and its owner will be notified."
                ))
            }
            .task {
                await viewModel.fetchDiwaniyas()
            }
            .onAppear {
                NewContentTracker.shared.markSeen(.diwaniyas)   // «النقاط الصفراء»: فُتح القسم
                viewModel.canModerate = authVM.canModerate
                viewModel.authVM = authVM
                viewModel.notificationVM = notificationVM
                rebuildVisibleDiwaniyas(viewModel.diwaniyas, animated: false)
            }
            // كل تغيير في القائمة (جلب، تعديل، اعتماد، حذف) — لا العدد وحده (التعديل كان لا يظهر حتى الرجوع للصفحة)
            .onReceive(viewModel.$diwaniyas) { rebuildVisibleDiwaniyas($0, animated: true) }
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



    // MARK: - الظاهرة للمستخدم

    /// المعتمدة للجميع، والمعلّقة للإدارة ولصاحبها فقط
    private func rebuildVisibleDiwaniyas(_ list: [Diwaniya], animated: Bool) {
        let userId = authVM.currentUser?.id
        let canModerate = authVM.canModerate
        let visible = list.filter { diwaniya in
            if diwaniya.approvalStatus == ApprovalStatus.approved.rawValue { return true }
            if diwaniya.approvalStatus == ApprovalStatus.pending.rawValue {
                return canModerate || diwaniya.ownerId == userId
            }
            return false
        }
        // الاعتماد ينقل البطاقة لمكانها في الأسبوع بنابض هادئ — «تقليل الحركة»: تلاشٍ قصير
        withAnimation(animated ? (reduceMotion ? DSMotion.fade : DS.Anim.smooth) : nil) {
            cachedVisibleDiwaniyas = visible
        }
    }

    // MARK: - إجراءات البطاقة

    private var cardActions: DiwaniyaCardActions {
        DiwaniyaCardActions(
            currentUserId: authVM.currentUser?.id,
            canDeleteAny: authVM.canDeleteDiwaniyas,
            canApprove: authVM.canApproveContent,
            edit: { diwaniyaToEdit = $0 },
            delete: { diwaniyaToDelete = $0 },
            report: { diwaniyaToReport = $0 },
            approve: { approve($0) },
            reject: { diwaniyaToReject = $0 }
        )
    }

    /// الاعتماد من البطاقة مباشرة (بلا تأكيد — مثل المشاريع)، ثم لحظة «تم الاعتماد»
    private func approve(_ diwaniya: Diwaniya) {
        guard let adminId = authVM.currentUser?.id else { return }
        Task {
            if await viewModel.approveFromSection(diwaniya, adminId: adminId) {
                DSMomentToast.show(L10n.t("تم الاعتماد", "Approved"), moment: .approved, section: .diwaniyas)
            }
        }
    }

    // MARK: - Empty State
    private var emptyStateView: some View {
        // الصفحة الفاضية الموحّدة: مجسّم «المجلس» + عنوان + سطر + زرّ الإضافة
        DSEmptyView(L10n.t("لا توجد ديوانيات", "No Diwaniyas Yet"),
                    message: authVM.canApproveContent
                        ? L10n.t("أضف ديوانية ليعرف الأهل مواعيدها.", "Add a diwaniya so family know when it meets.")
                        : L10n.t("أضف ديوانيتك ليعرف الأهل مواعيدها.\nتُعرض بعد موافقة الإدارة.",
                                 "Add your diwaniya so family know when it meets.\nIt appears after admin approval."),
                    section: .diwaniyas,
                    actionTitle: L10n.t("إضافة ديوانية", "Add Diwaniya"), actionIcon: "plus") {
            showingAddRequest = true
        }
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
                // مربّعات الاختيار الموحّدة (`DSOptionTiles`) برمز كل نوع: «مجلس» / «راية»
                DSOptionTiles(DiwaniyaKind.allCases.map { DSOptionTile($0, title: $0.title, icon: $0.icon, tint: $0.tint) },
                              selection: $kind, columns: 2)
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
                HStack(spacing: DS.Spacing.xsm) {
                    ForEach(Self.weekDays, id: \.id) { day in dayCircle(day.id, name: L10n.t(day.ar, day.en)) }
                }
                if !daysDisplayText.isEmpty {
                    Text(daysDisplayText)
                        .dsFont(.caption)
                        .foregroundColor(kind.tint.dsReadableGlyph)
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
                        // قرص «مجسّمات» الموحّد بمقاس أيقونة الحقل داخل المربّع (لون المعنى: أحمر/أخضر)
                        DSStateIcon(isClosed.wrappedValue ? "lock.fill" : "lock.open.fill",
                                    tint: isClosed.wrappedValue ? DS.Color.error : DS.Color.success,
                                    size: DSBox.fieldIcon)
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(isClosed.wrappedValue ? L10n.t("متوقفة حالياً", "Currently closed")
                                                       : L10n.t("مفتوحة ونشطة", "Open and active"))
                                .dsFont(.rowTitle)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(L10n.t("إيقافها يُظهرها «مغلقة» في القائمة", "Closing shows it as closed"))
                                .dsFont(.footnoteCompact)
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
                    // صفّ بإطار حقول المربّع الموحّد
                    .dsRowBox()
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

    private func dayCircle(_ id: Int, name: String) -> some View {
        let on = selectedDays.contains(id)
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) {
                if on { selectedDays.remove(id) } else { selectedDays.insert(id) }
            }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(Self.dayLetters[id])
                .dsFont(.rowTitle)
                .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Icon.sizeSm)
                .background(Circle().fill(on ? kind.tint : DS.Color.background))
                .overlay(Circle().strokeBorder(on ? Color.clear : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                               lineWidth: DS.Border.width))
                .scaleEffect(on && !reduceMotion ? 1.06 : 1)
                // الدائرة ٣٨ ← مساحة ضغط ٤٤ ارتفاعاً، وعرضاً حتى نصف المسافة (٣) بين
                // الدوائر فتتلاصق المساحات بلا تداخل — التخطيط كما هو
                .tapArea(top: (DS.Icon.tapTarget - DS.Icon.sizeSm) / 2, leading: DS.Spacing.xsm / 2,
                         bottom: (DS.Icon.tapTarget - DS.Icon.sizeSm) / 2, trailing: DS.Spacing.xsm / 2)
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.xsm), count: 4),
                      spacing: DS.Spacing.xsm) {
                ForEach(Self.timeSlots, id: \.self) { time in
                    let on = selectedTimes.contains(time)
                    let slot = RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.68)) {
                            if on { selectedTimes.remove(time) } else { selectedTimes.insert(time) }
                        }
                    } label: {
                        Text(L10n.t("\(time) م", "\(time) PM"))
                            .dsFont(on ? .chip : .subtitle)
                            .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textSecondary)
                            .frame(maxWidth: .infinity).frame(height: DS.Icon.rowLarge)
                            .background(slot.fill(on ? kind.tint : DS.Color.surface))
                            .overlay(slot.strokeBorder(on ? Color.clear : DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                                       lineWidth: DS.Border.width))
                            // مساحة الضغط حتى نصف المسافة (٣) بين الخانات من كل جهة — ٤٢ ارتفاعاً
                            // بلا تداخل ولا تغيير في الشبكة (الصفوف متباعدة ٦ فقط)
                            .tapArea(top: DS.Spacing.xsm / 2, leading: DS.Spacing.xsm / 2,
                                     bottom: DS.Spacing.xsm / 2, trailing: DS.Spacing.xsm / 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if !timeDisplayText.isEmpty {
                Text(timeDisplayText)
                    .dsFont(.sectionTitle)
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
                // الشريحة الموحّدة (`DSChipButton`) — مثل «إزالة» في مربّع المكتبة، بمساحة ضغط ٤٤
                DSChipButton(L10n.t("إزالة الرقم", "Remove"), icon: "trash", tint: DS.Color.error, size: .mini) {
                    phoneNumber = ""
                }
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
        if success {
            dismiss()
            // طلب العضو يظهر له فوراً في «بانتظار الاعتماد» (المعتمَد يُجلب داخل الإضافة نفسها)
            if !canAutoApprove { Task { await viewModel.fetchDiwaniyas() } }
        } else {
            showError = true
        }
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
