import SwiftUI
import PhotosUI
import UserNotifications

// MARK: - «كمّل ملفك بصورة» (طلب المالك ٢٠٢٦-١١-٠٥، العينة «ج»)
//
// مربّع واحد بعد الفتح لعضو مفعّل بلا صورة (الذكور فقط حالياً)، مرة لكل فتح على الأكثر. ظهوره يحفظ تاريخاً لكل حساب
// (أي إغلاق — «لاحقاً» أو الإغلاق أو السحب — يؤجّله، P1 ٢٠٢٦-١١-٢٦) ويرجع بعد `app_config.photo_reminder_days` يوم
// (٠ أو غائب = لا يظهر أبداً)، ولا يظهر في يوم ظهر فيه مربّع طلب الإدارة. لا يظهر لحساب مراجعة Apple ولا للمتوفى،
// ولا فوق «الموافقة على الشروط» أو طلب إذن الإشعارات أو أي مربّع مفتوح. الدخول والتحديث الإجباري والصيانة بلا تبويبات أصلاً
// فلا يعمل فيها (`RootView`) ويُفحصان هنا أيضاً لأن الإعدادات قد تصل بعد ظهور التبويبات.

/// تغيير الصورة الشخصية — المسار الواحد لمعاينة «حسابي» وهذا المربّع: أول ٣ تغييرات تُرفع مباشرة،
/// وبعدها تُرسل اقتراحاً للإدارة (نفس قاعدة شاشة تعديل البيانات)
enum ProfileAvatarChange {
    enum Outcome { case changed, sentForApproval, failed }

    struct Result {
        let outcome: Outcome
        let message: String
    }

    @MainActor
    static func run(_ image: UIImage, for member: FamilyMember,
                    memberVM: MemberViewModel, adminRequestVM: AdminRequestViewModel) async -> Result {
        let failed = Result(outcome: .failed, message: L10n.t("تعذّر رفع الصورة. يرجى المحاولة مرة أخرى.", "Couldn't upload the photo. Try again."))
        let cooldown = ProfileEditCooldown.shared
        await cooldown.refresh()
        if cooldown.canEdit(.avatar) {
            guard await memberVM.uploadAvatar(image: image, for: member.id) else { return failed }
            cooldown.recordEdit(.avatar)
            return Result(outcome: .changed, message: L10n.t("تم تغيير الصورة", "Photo changed"))
        }
        guard let url = await adminRequestVM.uploadPhotoSuggestion(image) else { return failed }
        let ok = await adminRequestVM.submitTreeEditRequest(from: .photoReminder, payload: .make(
            action: .addPhoto,
            targetMemberId: member.id.uuidString,
            targetMemberName: member.fullName,
            newPhotoUrl: url,
            notes: L10n.t("تعديل صورة بعد تجاوز حد التعديلات", "Photo edit after reaching the edit limit")
        ))
        return ok
            ? Result(outcome: .sentForApproval,
                     message: L10n.t("تجاوزت ٣ تغييرات — أُرسلت الصورة للإدارة للموافقة", "Over 3 changes — sent to the admins for approval"))
            : Result(outcome: .failed, message: L10n.t("تعذّر إرسال الطلب. يرجى المحاولة مرة أخرى.", "Couldn't send the request. Try again."))
    }
}

@MainActor
enum PhotoReminder {
    static let daysKey = "photo_reminder_days"
    /// مرة لكل فتح للتطبيق (عمر العملية)
    static var shownThisLaunch = false
    /// فحص كل ثانية، ولا مربّع بعد نصف دقيقة من انتظار ما يمنعه — يرجع في الفتح القادم
    static let checkIntervalNanos: UInt64 = 1_000_000_000
    static let maxChecks = 30

    private static func laterKey(_ userId: UUID) -> String { "photoReminderLater.\(userId.uuidString)" }

    static func hasNoPhoto(_ member: FamilyMember) -> Bool {
        [member.avatarUrl, member.photoURL].allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// عضو مفعّل حي بلا صورة — الذكور فقط حالياً (قرار المالك)
    static func isEligible(_ member: FamilyMember) -> Bool {
        member.status == .active && member.role != .pending && member.isDeceased != true
            && !member.isFemale && hasNoPhoto(member)
    }

    /// لم يضغط «لاحقاً» بعد، أو مضت المدة منذ ضغطها
    static func isDue(userId: UUID, days: Int, now: Date = Date()) -> Bool {
        guard days > 0 else { return false }
        guard let later = UserDefaults.standard.object(forKey: laterKey(userId)) as? Date else { return true }
        guard let due = Calendar.current.date(byAdding: .day, value: days, to: later) else { return false }
        return now >= due
    }

    static func snooze(userId: UUID, now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: laterKey(userId))
    }

    /// مربّع أو ورقة مفتوحة فوق التبويبات الآن — غطاء ثانٍ لا يُعرض فوقها
    static var isSomethingPresented: Bool {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.windowLevel == .normal && !$0.isHidden }
        let window = windows.first(where: \.isKeyWindow) ?? windows.first
        return window?.rootViewController?.presentedViewController != nil
    }
}

/// يقرّر متى يظهر المربّع — على `MainTabView`، بعد انتهاء فحص إذن الإشعارات (`blocked`).
/// «طلب تغيير الصورة» / «أضف صورتك الشخصية» من الإدارة يسبق «كمّل ملفك بصورة» بنفس قواعد الظهور، ويظهر **مرة لكل
/// إشعار** (P1، طلب المالك ٢٠٢٦-١١-٢٦ «مابي التنبيه يكون بشكل يومي كل ما يدخل التطبيق»): بعد الطلب الأول وبعد كل تذكير
/// (`notified_at` يتغيّر) — `photoRequestSeen.<userId>` = معرّف الطلب + `notified_at`، يُحفظ عند الظهور فأي إغلاق أو إضافة
/// الصورة = رآه. الضغط على إشعاره من خارج التطبيق يفتحه دائماً (`.openPhotoChangeRequest`). الطلب يبقى مفتوحاً على
/// السيرفر والتذكير يكمل بجدوله.
struct PhotoReminderGate: ViewModifier {
    /// فحص الإشعارات لم ينتهِ أو مربّعه ظاهر
    let blocked: Bool
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    /// المربّع المعروض — عنصر واحد يحمل العضو والطلب (`dsCenterBox(item:)` يمرّره لمحتوى الغطاء ويُبقيه أثناء حركة
    /// الخروج). كان العضو حالةً منفصلة يقرؤها محتوى الغطاء فيصله nil (تعتيم بلا مربّع) — فحص ٢٠٢٦-١١-١١
    @State private var shown: Shown?

    private struct Shown: Identifiable {
        let id = UUID()
        let member: FamilyMember
        /// طلب الإدارة — nil = «كمّل ملفك بصورة»
        let request: PhotoChangeRequest?
    }

    private var isPresented: Bool { shown != nil }

    private enum Readiness { case show(FamilyMember), showRequest(FamilyMember, PhotoChangeRequest), wait, never }

    func body(content: Content) -> some View {
        content
            .task(id: blocked) {
                guard !blocked else { return }
                await attempt()
            }
            // إشعار «طلب تغيير الصورة الشخصية» من خارج التطبيق
            .onReceive(NotificationCenter.default.publisher(for: .openPhotoChangeRequest)) { _ in
                Task { await attempt(fromTap: true) }
            }
            .dsCenterBox(item: $shown) { box in
                PhotoReminderBox(member: box.member, request: box.request, onClose: { shown = nil })
                    .environmentObject(memberVM)
                    .environmentObject(adminRequestVM)
            }
    }

    /// `fromTap`: من الإشعار — طلب الإدارة وحده، ولو ظهر مربّع في هذا الفتح
    private func attempt(fromTap: Bool = false) async {
        guard fromTap || !PhotoReminder.shownThisLaunch else { return }
        // طلب الإدارة يُجلب مرة لكل محاولة (لا كل ثانية) — nil = لم يُجلب بعد
        var fetched: PhotoChangeRequest?? = nil
        for _ in 0..<PhotoReminder.maxChecks {
            try? await Task.sleep(nanoseconds: PhotoReminder.checkIntervalNanos)
            if Task.isCancelled || isPresented { return }
            switch await readiness(requestOnly: fromTap, fetched: &fetched) {
            case .never:
                return
            case .wait:
                continue
            case .show(let found):
                if Task.isCancelled || isPresented { return }
                PhotoReminder.shownThisLaunch = true
                // أي إغلاق يؤجّله `photo_reminder_days` — لا يرجع في الفتح القادم
                PhotoReminder.snooze(userId: found.id)
                shown = Shown(member: found, request: nil)
                return
            case .showRequest(let found, let pending):
                if Task.isCancelled || isPresented { return }
                PhotoReminder.shownThisLaunch = true
                // مرة لكل إشعار: ظهر = رآه (الإغلاق و«لاحقاً» وإضافة الصورة سواء)
                PhotoChangeRequestStore.markSeen(pending, userId: found.id)
                shown = Shown(member: found, request: pending)
                return
            }
        }
    }

    /// طلب الإدارة المفتوح لم يُرسَل عنه اقتراح من هذا الجهاز بعد — الفشل/السيرفر القديم = لا طلب
    private func pendingRequest(for user: FamilyMember, fetched: inout PhotoChangeRequest??) async -> PhotoChangeRequest? {
        if fetched == nil { fetched = .some(await PhotoChangeRequestStore.shared.refreshMine(userId: user.id)) }
        guard let found = fetched ?? nil, !PhotoChangeRequestStore.isSentForApproval(found.id) else { return nil }
        return found
    }

    private func readiness(requestOnly: Bool, fetched: inout PhotoChangeRequest??) async -> Readiness {
        guard authVM.status == .fullyAuthenticated, let user = authVM.currentUser else { return .wait }
        #if DEBUG
        // `-tmpPhotoChangePreview 1`: مربّع الطلب بسبب تجريبي بلا سيرفر (لقطات الشاشة)
        if PhotoChangeRequestStore.isDebugPreview {
            guard !PhotoReminder.isSomethingPresented else { return .wait }
            guard let preview = await pendingRequest(for: user, fetched: &fetched) else { return .never }
            return .showRequest(user, preview)
        }
        #endif
        if AppBuild.current < (appSettingsVM.settings.iosMinBuild ?? 0) && user.role != .owner { return .never }
        if appSettingsVM.settings.maintenanceMode && !authVM.canModerate { return .never }

        // طلب الإدارة («أضف صورتك» / «غيّر صورتك») — قبل «كمّل ملفك بصورة»، بنفس قواعد الظهور أدناه، ولأي جنس
        if user.status == .active && user.role != .pending && user.isDeceased != true,
           let pending = await pendingRequest(for: user, fetched: &fetched) {
            // عند الفتح: مرة لكل إشعار. من الإشعار نفسه: دائماً. طلب مفتوح رآه = لا «كمّل ملفك بصورة» فوقه أيضاً
            guard PhotoNudgeLogic.showsRequestBox(token: pending.seenToken,
                                                  seen: PhotoChangeRequestStore.seenToken(userId: user.id),
                                                  fromTap: requestOnly) else { return .never }
            if let blocked = await displayBlocked(user) { return blocked }
            return .showRequest(user, pending)
        }
        if requestOnly { return .never }
        // لا «كمّل ملفك بصورة» في يوم ظهر فيه مربّع طلب الإدارة
        guard PhotoNudgeLogic.generalPopupAllowed(requestBoxDay: PhotoChangeRequestStore.requestBoxDay(userId: user.id),
                                                  today: PhotoNudgeLogic.dayKey(Date())) else { return .never }

        guard PhotoReminder.isEligible(user) else { return .never }
        // نسخة الشجرة قد تكون أحدث من الجلسة (صورة أُضيفت من جهاز آخر)
        if let tree = memberVM.member(byId: user.id), !PhotoReminder.hasNoPhoto(tree) { return .never }

        // ٠ أو مفتاح غائب أو جلب فاشل = لا يظهر (`AppConfigValues` يجلبها مع بوابة الشروط)
        await AppConfigValues.shared.refresh()
        let config = AppConfigValues.shared
        guard !config.values.isEmpty else { return .wait }
        guard PhotoReminder.isDue(userId: user.id, days: config.int(PhotoReminder.daysKey, default: 0)) else { return .never }

        if let blocked = await displayBlocked(user) { return blocked }
        return .show(user)
    }

    /// قواعد الظهور المشتركة — nil = يُعرض الآن
    private func displayBlocked(_ user: FamilyMember) async -> Readiness? {
        // حساب مراجعة Apple: لا يُعرض إلا بعد قراءة مؤكدة أنه ليس منها
        let review = ReviewCardStore.shared
        await review.load(for: user.id)
        guard review.isCardLoaded(for: user.id) else { return .wait }
        if review.card != nil || review.isReview(user.id) { return .never }

        let terms = TermsAcceptanceStore.shared
        guard terms.statusChecked, !terms.needsAcceptance else { return .wait }
        // طلب إذن الإشعارات من النظام ما زال أمام المستخدم
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus != .notDetermined else { return .wait }
        guard !PhotoReminder.isSomethingPresented else { return .wait }
        return nil
    }
}

/// المربّع نفسه — نوع مستقل (حارس المكدس). الصورة بمسار «حسابي»: المعرض ← القصّ الدائري ← الرفع.
/// `request` = طلب الإدارة: بلا صورة «أضف صورتك الشخصية» (P1)، وبصورة «يرجى تغيير صورتك الشخصية» بالسبب والصورة
/// الحالية في الدائرة. يظهر مرة لكل إشعار (`PhotoReminderGate`)، ويرجع مع التذكير التالي ما دام الطلب مفتوحاً
struct PhotoReminderBox: View {
    let member: FamilyMember
    var request: PhotoChangeRequest? = nil
    let onClose: () -> Void
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel

    private struct CropItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    @State private var pickerItem: PhotosPickerItem?
    @State private var cropItem: CropItem?
    @State private var newImage: UIImage?
    @State private var isUploading = false
    @State private var resultMessage: String?
    /// أُرسلت للموافقة — يبقى «إغلاق» وحده
    @State private var finished = false

    @State private var showPicker = false

    /// طلب «غيّر صورتك» (له صورة) — بلا صورة الطلب «أضف صورتك الشخصية» (P1)
    private var isChangeRequest: Bool {
        request != nil && PhotoNudgeLogic.memberBox(hasPhoto: !PhotoReminder.hasNoPhoto(member)) == .change
    }

    private var boxTitle: String {
        guard request != nil else { return L10n.t("الصورة الشخصية", "Profile photo") }
        return isChangeRequest ? L10n.t("يرجى تغيير صورتك الشخصية", "Please change your profile photo")
                               : L10n.t("أضف صورتك الشخصية", "Add your profile photo")
    }

    var body: some View {
        // هيكل المربّعات الموحّد (`DSComposer`، طلب المالك ٢٠٢٦-١١-١١): رأس كحلي، المحتوى، ثم «أضف صورة» و«لاحقاً» الخفيف
        DSComposer(
            title: boxTitle,
            subtitle: request != nil ? L10n.t("طلب من الإدارة", "A request from the admins")
                                     : L10n.t("أكمل ملفك بصورة", "Complete your profile with a photo"),
            icon: isChangeRequest ? "camera.badge.ellipsis" : "camera.fill",
            tint: DS.Color.actionNavy,
            actionTitle: isChangeRequest ? L10n.t("تغيير الصورة", "Change photo") : L10n.t("أضف صورة", "Add a photo"),
            actionIcon: "photo.on.rectangle",
            showsAction: !finished,
            cancelTitle: finished ? L10n.t("إغلاق", "Close") : L10n.t("لاحقاً", "Later"),
            canSubmit: !isUploading,
            isBusy: isUploading,
            onSubmit: { showPicker = true },
            onCancel: {
                // طلب الإدارة: بلا تأجيل — يرجع في الفتح القادم ما دام مفتوحاً
                if !finished && request == nil { PhotoReminder.snooze(userId: member.id) }
                onClose()
            }
        ) {
            VStack(spacing: DS.Spacing.md) {
                ring
                if let request, isChangeRequest, !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(L10n.t("السبب: \(request.reason)", "Reason: \(request.reason)"))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(introText)
                    .dsFont(.callout)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let resultMessage {
                    Text(resultMessage)
                        .dsFont(.callout)
                        .foregroundColor(finished ? DS.Color.textPrimary : DS.Color.error)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cropItem = CropItem(image: image)
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(item: $cropItem) { item in
            ImageCropperView(image: item.image, cropShape: .circle) { cropped in
                cropItem = nil
                upload(cropped)
            } onCancel: {
                cropItem = nil
            }
        }
    }

    private var introText: String {
        guard let request else {
            return L10n.t("تظهر صورتك في الشجرة، وتساعد أفراد العائلة على التعرّف عليك.",
                          "Your photo appears in the tree and helps family recognize you.")
        }
        guard isChangeRequest else {
            return L10n.t("تطلب منك الإدارة إضافة صورة شخصية لملفك. تظهر صورتك في الشجرة، وتساعد أفراد العائلة على التعرّف عليك.",
                          "The admins ask you to add a profile photo. It appears in the tree and helps family recognize you.")
        }
        return request.hidePhoto
            ? L10n.t("صورتك الحالية مخفية عن الأعضاء حتى تغيّرها. يرجى اختيار صورة شخصية واضحة لك.",
                     "Your current photo is hidden from members until you change it. Please choose a clear photo of yourself.")
            : L10n.t("يرجى اختيار صورة شخصية واضحة لك.", "Please choose a clear photo of yourself.")
    }

    private var ring: some View {
        ZStack {
            if let newImage {
                Image(uiImage: newImage).resizable().scaledToFill()
            } else if isChangeRequest {
                // الصورة الحالية المطلوب تغييرها
                DSMemberAvatar(name: member.fullName, avatarUrl: member.avatarUrl, size: DS.Icon.profileAvatarRing)
                    .accessibilityLabel(L10n.t("صورتك الحالية", "Your current photo"))
            } else {
                Circle().fill(DS.Color.accent.opacity(DS.Opacity.tintFill))
                Image(systemName: "camera.fill")
                    .dsGlyph(DS.Glyph.xxl)
                    .foregroundColor(DS.Color.accent)
                    .accessibilityHidden(true)
            }
            if isUploading {
                DS.Color.hierarchicalSecondary
                DSPageLoader(section: .profile)
            }
        }
        .frame(width: DS.Icon.profileAvatarRing, height: DS.Icon.profileAvatarRing)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(DS.Color.accent, style: DSAddChipLabel.dash))
    }

    private func upload(_ image: UIImage) {
        newImage = image
        isUploading = true
        resultMessage = nil
        Task {
            let result = await ProfileAvatarChange.run(image, for: member, memberVM: memberVM, adminRequestVM: adminRequestVM)
            isUploading = false
            switch result.outcome {
            case .changed:
                // طلب الإدارة: السيرفر أغلقه مع الصورة الجديدة (`trg_zzzz_photo_change_resolve`)
                if request != nil { PhotoChangeRequestStore.shared.clearMine() }
                onClose()
            case .sentForApproval:
                // لا صورة بعد حتى توافق الإدارة — لا يرجع التذكير قبل مدته، ولا طلب الإدارة من هذا الجهاز
                // (يُغلق على السيرفر حين تُعتمد الصورة)
                if let request {
                    PhotoChangeRequestStore.markSentForApproval(request.id)
                } else {
                    PhotoReminder.snooze(userId: member.id)
                }
                resultMessage = result.message
                finished = true
            case .failed:
                newImage = nil
                resultMessage = result.message
            }
        }
    }
}
