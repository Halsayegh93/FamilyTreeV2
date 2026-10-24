import SwiftUI

/// شاشة إدارة طلبات تعديل الشجرة — مفصولة عن AdminAllRequestsView.
/// تعرض 7 فلاتر حسب نوع الإجراء (إضافة / تعديل اسم / رقم / ميلاد / وفاة / حذف / أخرى).
///
/// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧، «أسلوب واحد» ٢٠٢٦-١٠-٠٧): الرأس الملوّن
/// الموحّد (`dsSubPageHeader`) ← صفّ الأرقام الحيّة ← فلاتر الأنواع بعددها ← بطاقة لكل طلب بإطار صفوف
/// المربّعات (أيقونة النوع + اسم العضو + عمر الطلب ← التفاصيل ← «موافقة» / «رفض» بالزرّ الواحد).
/// الاستدعاءات والصلاحيات (`canApprove(_:)` و`canRejectRequests`) كما كانت تماماً.
struct AdminTreeEditRequestsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedAction: TreeEditAction = .add
    @State private var rejectingRequest: AdminRequest? = nil
    @State private var rejectReasonText: String = ""
    @State private var showRejectAlert: Bool = false
    /// «مسار الموافقات»: الطلب المفتوح في مربّع المسار
    @State private var approvalRequest: AdminRequest? = nil
    /// اكتمل أول جلب — قبله «—» في الأرقام وبطاقة تحميل (إن لم تكن هناك طلبات محمّلة أصلاً)
    @State private var hasLoaded = false
    /// آخر جلب انتهى والجهاز غير متصل — لبطاقة «تعذّر التحميل» بدل «لا توجد طلبات» المضلِّلة
    /// (تبقى حتى جلب ناجح: السحب للتحديث أو «إعادة المحاولة»)
    @State private var lastFetchOffline = false

    private let allActions: [TreeEditAction] = [.add, .editName, .editPhone, .editBirth, .deceased, .delete, .other]

    /// لون مجال «الشجرة والأعضاء»
    private let pageTint = DS.Color.composerProject

    private func color(for action: TreeEditAction) -> Color {
        switch action {
        case .add: return DS.Color.palm
        case .editName: return DS.Color.info
        case .editPhone: return AppSection.admin.ink
        case .editBirth: return DS.Color.palm
        case .deceased: return DS.Color.textTertiary
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return AppSection.admin.ink
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        }
    }

    /// عدد الطلبات لكل نوع — مرور واحد بدل فلترة القائمة لكل شريحة
    private var actionCounts: [TreeEditAction: Int] {
        var counts: [TreeEditAction: Int] = [:]
        for request in adminRequestVM.treeEditRequests {
            if let action = request.treeEditPayload?.resolvedAction {
                counts[action, default: 0] += 1
            }
        }
        return counts
    }

    private var filteredRequests: [AdminRequest] {
        // «مسار الموافقات»: ما ينتظرك أولاً (مطفأ = الترتيب كما كان)
        adminRequestVM.approvalOrdered(
            adminRequestVM.treeEditRequests.filter { $0.treeEditPayload?.resolvedAction == selectedAction })
    }

    /// الأدوار مجالات (٢٠٢٦-٠٩-٢١، CLAUDE.md): قبول طلبات الشجرة للمالك والمدير والمراقب —
    /// نفس «طلبات المراجعة» (`canApproveTreeRequests`). كان هنا تقسيم قديم يعطي المشرف
    /// «الإضافة» ويحرم المراقب من بعض الأنواع، والسيرفر يرفضه أصلاً.
    private func canApprove(_ action: TreeEditAction) -> Bool {
        authVM.canApproveTreeRequests
    }

    /// أول تحميل ولا طلبات محمّلة بعد
    private var isInitialLoading: Bool {
        !hasLoaded && adminRequestVM.treeEditRequests.isEmpty
    }

    /// الجلب انتهى بلا طلبات والجهاز غير متصل — القائمة الفارغة هنا ليست «لا توجد طلبات»
    private var loadFailed: Bool {
        hasLoaded && adminRequestVM.treeEditRequests.isEmpty && lastFetchOffline
    }

    /// نفس الجلب السابق تماماً — ويحفظ هل انتهى بلا اتصال
    private func fetchRequests() async {
        await adminRequestVM.fetchTreeEditRequests(force: true)
        lastFetchOffline = !NetworkMonitor.shared.isConnected
    }

    var body: some View {
        // تُدفع داخل شريط تنقّل لوحة الإدارة (navigationDestination) — بلا NavigationStack داخلي
        // حتى لا يظهر شريطان، والرجوع هو زر أبل المعتاد بدل «إغلاق».
        Group {
            // صفّ الأرقام ← الفلاتر ← الطلبات: تتمرّر معاً (والسحب للتحديث يعمل حتى والقائمة فارغة)
            ScrollView(showsIndicators: false) {
                pageContent
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xxxl)
            }
            // الرأس الملوّن الموحّد (بدل شريط النظام وبطاقة الرأس) — الوصف: ما يعتمده المشاهد
            .dsSubPageHeader(L10n.t("طلبات الشجرة", "Tree Requests"), subtitle: heroSubtitle)
            .dsAlert(
                L10n.t("سبب الرفض", "Rejection Reason"),
                isPresented: $showRejectAlert
            ) {
                TextField(L10n.t("اكتب سبب الرفض (اختياري)", "Reason (optional)"), text: $rejectReasonText)
                Button(L10n.t("رفض", "Reject"), role: .destructive) {
                    if let req = rejectingRequest {
                        let reason = rejectReasonText.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await adminRequestVM.rejectTreeEditRequest(request: req, reason: reason.isEmpty ? nil : reason) }
                    }
                    rejectingRequest = nil
                    rejectReasonText = ""
                }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {
                    rejectingRequest = nil
                    rejectReasonText = ""
                }
            } message: {
                Text(L10n.t("سيظهر السبب في إشعار للمستخدم.", "The reason will appear in a notification to the user."))
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            // «مسار الموافقات»: مربّع المسار — التنفيذ والرفض بمساري الموافقة/الرفض نفسيهما
            .dsCenterBox(item: $approvalRequest) { request in
                approvalBox(for: request)
            }
            .task {
                await adminRequestVM.refreshApprovalsFlag()
                await fetchRequests()
                withAnimation(reduceMotion ? nil : DS.Anim.smooth) { hasLoaded = true }
            }
            .refreshable { await fetchRequests() }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - هيكل الصفحة

    private var pageContent: some View {
        let counts = actionCounts
        let total = allActions.reduce(0) { $0 + (counts[$1] ?? 0) }
        let requests = filteredRequests

        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            heroSection(counts: counts, total: total)

            if isInitialLoading {
                DSPageLoader(L10n.t("جارٍ تحميل الطلبات…", "Loading requests…"), fillsSpace: false)
                    .padding(.top, DS.Spacing.xl)
                    .dsStaggerIn(1)
            } else if loadFailed {
                DSStateCard(icon: "wifi.exclamationmark",
                             title: L10n.t("تعذّر تحميل الطلبات", "Couldn't load requests"),
                             hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                             tint: DS.Color.error,
                             actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                             action: { Task { await fetchRequests() } })
                    .padding(.top, DS.Spacing.xs)
                    .dsStaggerIn(1)
            } else {
                // الفلاتر — تظهر فقط إذا في طلبات
                if total > 0 {
                    actionChips(counts)
                        .dsStaggerIn(1)
                }

                if requests.isEmpty {
                    emptyState(total: total, counts: counts)
                        .padding(.top, DS.Spacing.xs)
                        .dsStaggerIn(2)
                } else {
                    AdaptiveLazyStack(spacing: DS.Spacing.md) {
                        ForEach(Array(requests.enumerated()), id: \.element.id) { index, request in
                            requestCard(for: request)
                                .dsStaggerIn(min(index, 5) + 2)
                        }
                    }
                }
            }
        }
    }

    // MARK: - الأرقام السريعة (العنوان والوصف في الرأس الملوّن)

    private func heroSection(counts: [TreeEditAction: Int], total: Int) -> some View {
        DSStatsRow(heroStats(counts: counts, total: total), tint: pageTint)
    }

    /// ما يعتمده المشاهد — من نفس `canApprove(_:)` (المراقب: اسم/رقم/وفاة/حذف، المشرف: إضافة)
    private var heroSubtitle: String {
        let approvable = allActions.filter { canApprove($0) }
        if approvable.count == allActions.count {
            return L10n.t("إضافات الأعضاء وتعديلاتهم على الشجرة بانتظار قرارك",
                          "Members' additions and edits to the tree, awaiting your decision")
        }
        if approvable.isEmpty {
            return L10n.t("للاطلاع والمتابعة — الاعتماد للإدارة", "For follow-up — approval is up to the admins")
        }
        let ar = approvable.map(\.arabicLabel).joined(separator: "، ")
        let en = approvable.map(\.englishLabel).joined(separator: ", ")
        return L10n.t("تعتمد منها: \(ar)", "You can approve: \(en)")
    }

    /// ٣ أرقام حيّة من الطلبات المحمّلة أصلاً (بلا طلبات جديدة للسيرفر): المجموع (نفس مجموع
    /// الفلاتر)، النوع الأكثر طلباً، وما وصل اليوم — «—» أثناء التحميل الأول.
    private func heroStats(counts: [TreeEditAction: Int], total: Int) -> [DSHeroStat] {
        let pendingLabel = L10n.t("بانتظار المراجعة", "Awaiting review")
        let topLabel = L10n.t("الأكثر طلباً", "Most requested")
        let todayLabel = L10n.t("جديد اليوم", "New today")

        guard !isInitialLoading else {
            return [
                DSHeroStat(value: "—", label: pendingLabel, icon: "tray.full.fill"),
                DSHeroStat(value: "—", label: topLabel, icon: "chart.bar.fill"),
                DSHeroStat(value: "—", label: todayLabel, icon: "sparkles")
            ]
        }

        // الأكثر طلباً — عند التساوي يبقى الأسبق بترتيب الفلاتر
        var top: TreeEditAction? = nil
        var topCount = 0
        for action in allActions where (counts[action] ?? 0) > topCount {
            top = action
            topCount = counts[action] ?? 0
        }

        let visibleActions = Set(allActions)
        let today = adminRequestVM.treeEditRequests.filter { request in
            guard let action = request.treeEditPayload?.resolvedAction,
                  visibleActions.contains(action),
                  let date = Self.requestDate(request.createdAt) else { return false }
            return Calendar.current.isDateInToday(date)
        }.count

        let topStat: DSHeroStat
        if let top {
            topStat = DSHeroStat(value: "\(topCount)",
                                 label: L10n.t("الأكثر: \(top.arabicLabel)", "Top: \(top.englishLabel)"),
                                 icon: top.iconName)
        } else {
            topStat = DSHeroStat(value: "—", label: topLabel, icon: "chart.bar.fill")
        }

        return [
            DSHeroStat(value: "\(total)", label: pendingLabel, icon: "tray.full.fill"),
            topStat,
            DSHeroStat(value: "\(today)", label: todayLabel, icon: "sparkles")
        ]
    }

    // MARK: - الفلاتر

    /// نفس الفلاتر السبعة — العدد يظهر فقط إذا أكبر من صفر
    private func actionChips(_ counts: [TreeEditAction: Int]) -> some View {
        DSFilterChips(
            options: allActions.map { action in
                let n = counts[action] ?? 0
                return DSFilterOption(id: action,
                                      title: L10n.t(action.arabicLabel, action.englishLabel),
                                      icon: action.iconName,
                                      count: n > 0 ? n : nil)
            },
            selection: $selectedAction,
            tint: pageTint
        )
    }

    // MARK: - الحالة الفارغة

    @ViewBuilder
    private func emptyState(total: Int, counts: [TreeEditAction: Int]) -> some View {
        if total == 0 {
            DSEmptyView(L10n.t("لا توجد طلبات معلقة", "No pending requests"),
                        message: L10n.t("كل طلبات الشجرة متابَعة — ما فيه شي ينتظر قرارك",
                                        "All tree requests are handled — nothing is awaiting your decision"),
                        tint: DS.Color.success, style: .compact)
        } else if let next = allActions.first(where: { (counts[$0] ?? 0) > 0 }) {
            // هذا النوع فارغ وغيره فيه طلبات — زر يفتح أول نوع فيه طلبات
            let n = counts[next] ?? 0
            DSEmptyView(L10n.t("لا توجد طلبات", "No requests"),
                        message: L10n.t("سوف تظهر طلبات هذا النوع هنا.", "Requests of this type will appear here."),
                        actionTitle: L10n.t("عرض «\(next.arabicLabel)» (\(n))", "Show \(next.englishLabel) (\(n))"),
                        actionIcon: next.iconName, style: .compact) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                    selectedAction = next
                }
            }
        }
    }

    // MARK: - بطاقة الطلب

    /// بطاقة بإطار صفوف المربّعات: الرأس (أيقونة النوع + اسم العضو + النوع + عمر الطلب)،
    /// ثم التفاصيل تحت العنوان، ثم «موافقة» / «رفض» — بنفس الصلاحيات السابقة تماماً.
    @ViewBuilder
    private func requestCard(for request: AdminRequest) -> some View {
        let payload = request.treeEditPayload
        let action = payload?.resolvedAction ?? selectedAction
        let tint = color(for: action)
        let requesterName = memberVM.member(byId: request.requesterId)?.displayFullName ?? L10n.t("غير معروف", "Unknown")
        let targetName = memberVM.treeEditTargetName(payload) ?? request.member?.displayFullName ?? "—"
        // «مسار الموافقات» شغّال: شارة المرحلة وزرّ المسار بدل «موافقة / رفض»
        let flow = adminRequestVM.approvalSnapshot(for: request)
        let showApprove = flow == nil && canApprove(action)
        let showReject = flow == nil && authVM.canRejectRequests
        // مقدّم الطلب هو العضو نفسه (مقارنة كمعرّفات) → اسمه في العنوان مرة واحدة فقط (طلب المالك ٢٠٢٦-١٠-٠٧)
        let targetId = payload?.targetMemberId.flatMap { UUID(uuidString: $0) } ?? request.memberId
        let selfRequest = targetId == request.requesterId

        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // الرأس
            HStack(alignment: .center, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: action.iconName, tint: tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(targetName)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n.t(action.arabicLabel, action.englishLabel))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                // الشارة بمقاسها — الاسم الطويل يلتفّ بدل أن تنضغط
                pendingChip(Self.requestDate(request.createdAt))
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)

            // التفاصيل — تبدأ تحت العنوان (بعد عمود الأيقونة + المسافة)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                detailLines(for: request, payload: payload, action: action)

                if !selfRequest {
                    metaLine(icon: "person.fill", text: L10n.t("مقدم الطلب: ", "Requester: ") + requesterName)
                }

                if let createdAt = request.createdAt, !createdAt.isEmpty {
                    metaLine(icon: "clock", text: formatDate(createdAt))
                }

                // «طلب آخر» يعرض ملاحظته أعلاه («الطلب») — لا تتكرّر
                if action != .other, let notes = payload?.notes, !notes.isEmpty {
                    HStack(alignment: .top, spacing: DS.Spacing.xs) {
                        Image(systemName: "text.bubble")
                            .dsGlyph(DS.Glyph.xs, weight: .semibold)
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: DS.Glyph.md)
                            .padding(.top, DS.Spacing.xxs)
                            .accessibilityHidden(true)
                        Text(notes)
                            .dsFieldFont(.subtitle)
                            .foregroundColor(DS.Color.fieldValue)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, DS.Icon.row + DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let flow {
                let waiting = adminRequestVM.isApprovalWaitingForMe(flow)
                ApprovalStageChips(snapshot: flow, waitingForMe: waiting,
                                   holderLabel: adminRequestVM.approvalHolderLabel(flow))
                    .padding(.leading, DS.Icon.row + DS.Spacing.sm)
                // ينتظرك = الزرّ بتعبئة القسم، وإلا للاطّلاع (رمادي)
                DSButton(waiting ? L10n.t("المسار والقرار", "Path & decision") : L10n.t("عرض المسار", "View path"),
                         icon: "point.topleft.down.to.point.bottomright.curvepath.fill",
                         role: waiting ? nil : .cancel) {
                    approvalRequest = request
                }
                .padding(.top, DS.Spacing.xxs)
            }

            // القرار — نفس الصلاحيات تماماً، بالزرّ الواحد (الموافقة بتعبئة القسم، الرفض أحمر)
            if showApprove || showReject {
                HStack(spacing: DSBox.buttonSpacing) {
                    if showApprove {
                        DSButton(L10n.t("موافقة", "Approve"), icon: "checkmark.circle.fill") {
                            Task { await adminRequestVM.approveTreeEditRequest(request: request) }
                        }
                        .accessibilityLabel(L10n.t("موافقة — \(targetName)", "Approve — \(targetName)"))
                    }

                    if showReject {
                        DSButton(L10n.t("رفض", "Reject"), icon: "xmark.circle.fill", role: .destructive, tint: DS.Color.reject) {
                            rejectingRequest = request
                            rejectReasonText = ""
                            showRejectAlert = true
                        }
                        .accessibilityLabel(L10n.t("رفض — \(targetName)", "Reject — \(targetName)"))
                    }
                }
                .padding(.top, DS.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsRowBox()
    }

    // MARK: - «مسار الموافقات» (طلب المالك ٢٠٢٦-١٠-١٥)

    /// مربّع المسار لطلب شجرة: المسار ← تفاصيل الطلب ← السجل ← القرار
    @ViewBuilder
    private func approvalBox(for request: AdminRequest) -> some View {
        if let flow = adminRequestVM.approvalSnapshot(for: request) {
            let payload = request.treeEditPayload
            let action = payload?.resolvedAction ?? selectedAction
            ApprovalRequestBox(
                adminRequestVM: adminRequestVM,
                memberVM: memberVM,
                snapshot: flow,
                title: L10n.t(action.arabicLabel, action.englishLabel),
                subtitle: memberVM.treeEditTargetName(payload) ?? request.member?.displayFullName ?? L10n.t("طلب الشجرة", "Tree request"),
                icon: action.iconName,
                onExecute: {
                    approvalRequest = nil
                    Task {
                        await adminRequestVM.approveTreeEditRequest(request: request)
                        // «لحظة نجاح» (الدفعة ١٠)
                        AdminApprovalMoment.after(adminRequestVM, title: L10n.t("تم التنفيذ", "Carried out"))
                    }
                },
                onReject: { reason in
                    approvalRequest = nil
                    Task { await adminRequestVM.rejectTreeEditRequest(request: request, reason: reason) }
                },
                onClose: { approvalRequest = nil }
            ) {
                DSComposerSection(title: L10n.t("بيانات الطلب", "Request Info"), icon: "doc.text.fill",
                                  tint: AppSection.admin.ink, index: 1) {
                    detailLines(for: request, payload: payload, action: action)
                }
            }
        } else {
            // المسار أُطفئ أو أُغلق الطلب أثناء الفتح
            Color.clear.onAppear { approvalRequest = nil }
        }
    }

    // MARK: - تفاصيل الطلب حسب النوع

    @ViewBuilder
    private func detailLines(for request: AdminRequest, payload: TreeEditPayload?, action: TreeEditAction) -> some View {
        switch action {
        case .add:
            if let newName = payload?.newMemberName {
                detailRow(icon: "person.badge.plus", label: L10n.t("اسم الابن", "Son's name"), value: newName)
            }
            if let parentName = payload?.parentMemberName {
                detailRow(icon: "person.fill", label: L10n.t("الأب", "Parent"), value: parentName)
            }

        case .editName:
            if let currentName = payload?.targetMemberName {
                detailRow(icon: "person.fill", label: L10n.t("الاسم الحالي", "Current name"), value: currentName)
            }
            if let newName = payload?.newName {
                detailRow(icon: "pencil", label: L10n.t("الاسم الجديد", "New name"), value: newName, valueColor: DS.Color.info)
            }

        case .editPhone:
            if let currentPhone = request.member?.phoneNumber {
                detailRow(icon: "phone.fill", label: L10n.t("الرقم الحالي", "Current phone"),
                          value: Self.isolatedLTR(KuwaitPhone.display(currentPhone)))
            }
            if let newPhone = payload?.newPhone {
                detailRow(icon: "phone.arrow.up.right", label: L10n.t("الرقم الجديد", "New phone"),
                          value: Self.isolatedLTR(KuwaitPhone.display(newPhone)), valueColor: AppSection.admin.ink)
            }

        case .deceased:
            if let deathDate = payload?.deathDate {
                detailRow(icon: "calendar", label: L10n.t("تاريخ الوفاة", "Date of death"), value: deathDate)
            }

        case .addDeathDate:
            if let deathDate = payload?.deathDate, !deathDate.isEmpty {
                detailRow(icon: "calendar.badge.exclamationmark", label: L10n.t("تاريخ الوفاة", "Date of death"), value: deathDate)
            }

        case .addPhoto:
            if let photoStr = payload?.newPhotoUrl, let url = URL(string: photoStr) {
                detailRow(icon: "photo.badge.plus", label: L10n.t("الصورة المقترحة", "Suggested photo"), value: "", valueColor: AppSection.admin.ink)
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    DSPageLoader(fillsSpace: false)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Self.photoPreviewHeight)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }

        case .delete:
            if let reason = payload?.reason, !reason.isEmpty {
                detailRow(icon: "exclamationmark.triangle", label: L10n.t("السبب", "Reason"), value: reason, valueColor: DS.Color.error)
            }

        case .editBirth:
            if let newDate = (payload?.newBirthDate ?? payload?.newName), !newDate.isEmpty {
                detailRow(icon: "birthday.cake", label: L10n.t("تاريخ الميلاد الجديد", "New birth date"), value: newDate, valueColor: DS.Color.palm)
            }

        case .other:
            if let note = payload?.notes, !note.isEmpty {
                detailRow(icon: "square.and.pencil", label: L10n.t("الطلب", "Request"), value: note, valueColor: DS.Color.accent)
            }
        }
    }

    /// ارتفاع معاينة الصورة المقترحة
    private static let photoPreviewHeight: CGFloat = 160

    /// سطر تفصيل: أيقونة صغيرة + عنوان (`footnote`) + قيمة عريضة (`chip`)
    private func detailRow(icon: String, label: String, value: String, valueColor: Color = DS.Color.fieldLabel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xs, weight: .semibold)
                .foregroundColor(DS.Color.textTertiary)
                .frame(width: DS.Glyph.md)
                .accessibilityHidden(true)
            Text(label)
                .dsFieldFont(.footnote)
                .foregroundColor(DS.Color.fieldValue)
            Text(value)
                .dsFont(.chip)
                .foregroundColor(valueColor)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// معلومة صغيرة: أيقونة + نص (`footnote`) — مقدّم الطلب والتاريخ
    private func metaLine(icon: String, text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(dsSymbol: icon)
                .dsGlyph(DS.Glyph.xsCompact, weight: .semibold)
                .frame(width: DS.Glyph.md)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.footnote)
                .lineLimit(1)
        }
        .foregroundColor(DS.Color.textTertiary)
    }

    /// الأرقام تبقى بترتيبها من اليسار داخل سطر عربي
    private static func isolatedLTR(_ text: String) -> String {
        "\u{2066}\(text)\u{2069}"
    }

    // MARK: - عمر الطلب

    /// شارة «بانتظار» — بعمر الطلب إن عُرف تاريخه (اليوم، أمس، ٣ أيام…)
    private func pendingChip(_ date: Date?) -> some View {
        let text = date.map { ageText(days: daysWaiting(since: $0)) } ?? L10n.t("بانتظار", "Pending")
        return DSStatusChip(text: text, icon: "clock", tint: DS.Color.warning)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(date == nil ? text : L10n.t("بانتظار: \(text)", "Pending: \(text)"))
    }

    /// أيام الانتظار بالتقويم (اليوم = ٠)
    private func daysWaiting(since date: Date) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: Date())).day ?? 0
        return max(0, days)
    }

    private func ageText(days: Int) -> String {
        switch days {
        case ..<1:    return L10n.t("اليوم", "Today")
        case 1:       return L10n.t("أمس", "1 day")
        case 2:       return L10n.t("يومان", "2 days")
        case 3...10:  return L10n.t("\(days) أيام", "\(days) days")
        default:      return L10n.t("\(days) يوماً", "\(days) days")
        }
    }

    /// تاريخ الطلب من نصّ ISO — بمحلّلين ثابتين (البطاقات والأرقام تُرسم كثيراً)
    private static let isoWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func requestDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return isoWithFraction.date(from: raw) ?? isoPlain.date(from: raw)
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            display.locale = Locale(identifier: L10n.isArabic ? "ar" : "en_US")
            return display.string(from: date)
        }
        return iso
    }
}
