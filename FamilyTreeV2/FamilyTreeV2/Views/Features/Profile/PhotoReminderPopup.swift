import SwiftUI
import PhotosUI
import UserNotifications

// MARK: - «كمّل ملفك بصورة» (طلب المالك ٢٠٢٦-١١-٠٥، العينة «ج»)
//
// مربّع واحد بعد الفتح لعضو مفعّل بلا صورة (الذكور فقط حالياً)، مرة لكل فتح على الأكثر. «لاحقاً» يحفظ تاريخاً لكل حساب
// ويرجع بعد `app_config.photo_reminder_days` يوم (٠ أو غائب = لا يظهر أبداً). لا يظهر لحساب مراجعة Apple ولا للمتوفى،
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
        if cooldown.canEdit(.avatar) {
            guard await memberVM.uploadAvatar(image: image, for: member.id) else { return failed }
            cooldown.recordEdit(.avatar)
            return Result(outcome: .changed, message: L10n.t("تم تغيير الصورة", "Photo changed"))
        }
        guard let url = await adminRequestVM.uploadPhotoSuggestion(image) else { return failed }
        let ok = await adminRequestVM.submitTreeEditRequest(payload: .make(
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

/// يقرّر متى يظهر المربّع — على `MainTabView`، بعد انتهاء فحص إذن الإشعارات (`blocked`)
struct PhotoReminderGate: ViewModifier {
    /// فحص الإشعارات لم ينتهِ أو مربّعه ظاهر
    let blocked: Bool
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @EnvironmentObject private var appSettingsVM: AppSettingsViewModel
    /// يبقى بعد الإغلاق حتى تنتهي حركة خروج المربّع
    @State private var member: FamilyMember?
    @State private var isPresented = false

    private enum Readiness { case show(FamilyMember), wait, never }

    func body(content: Content) -> some View {
        content
            .task(id: blocked) {
                guard !blocked else { return }
                await attempt()
            }
            .dsCenterBox(isPresented: $isPresented) {
                if let member {
                    AnyView(PhotoReminderBox(member: member, onClose: { isPresented = false })
                        .environmentObject(memberVM)
                        .environmentObject(adminRequestVM))
                }
            }
    }

    private func attempt() async {
        guard !PhotoReminder.shownThisLaunch else { return }
        for _ in 0..<PhotoReminder.maxChecks {
            try? await Task.sleep(nanoseconds: PhotoReminder.checkIntervalNanos)
            if Task.isCancelled { return }
            switch await readiness() {
            case .never:
                return
            case .wait:
                continue
            case .show(let found):
                if Task.isCancelled { return }
                PhotoReminder.shownThisLaunch = true
                member = found
                isPresented = true
                return
            }
        }
    }

    private func readiness() async -> Readiness {
        guard authVM.status == .fullyAuthenticated, let user = authVM.currentUser else { return .wait }
        if AppBuild.current < (appSettingsVM.settings.iosMinBuild ?? 0) && user.role != .owner { return .never }
        if appSettingsVM.settings.maintenanceMode && !authVM.canModerate { return .never }
        guard PhotoReminder.isEligible(user) else { return .never }
        // نسخة الشجرة قد تكون أحدث من الجلسة (صورة أُضيفت من جهاز آخر)
        if let tree = memberVM.member(byId: user.id), !PhotoReminder.hasNoPhoto(tree) { return .never }

        // ٠ أو مفتاح غائب أو جلب فاشل = لا يظهر (`AppConfigValues` يجلبها مع بوابة الشروط)
        await AppConfigValues.shared.refresh()
        let config = AppConfigValues.shared
        guard !config.values.isEmpty else { return .wait }
        guard PhotoReminder.isDue(userId: user.id, days: config.int(PhotoReminder.daysKey, default: 0)) else { return .never }

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
        return .show(user)
    }
}

/// المربّع نفسه — نوع مستقل (حارس المكدس). الصورة بمسار «حسابي»: المعرض ← القصّ الدائري ← الرفع
struct PhotoReminderBox: View {
    let member: FamilyMember
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

    var body: some View {
        // هيكل المربّعات الموحّد (`DSComposer`، طلب المالك ٢٠٢٦-١١-١١): رأس كحلي، المحتوى، ثم «أضف صورة» و«لاحقاً» الخفيف
        DSComposer(
            title: L10n.t("الصورة الشخصية", "Profile photo"),
            subtitle: L10n.t("أكمل ملفك بصورة", "Complete your profile with a photo"),
            icon: "camera.fill",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("أضف صورة", "Add a photo"),
            actionIcon: "photo.on.rectangle",
            showsAction: !finished,
            cancelTitle: finished ? L10n.t("إغلاق", "Close") : L10n.t("لاحقاً", "Later"),
            canSubmit: !isUploading,
            isBusy: isUploading,
            onSubmit: { showPicker = true },
            onCancel: {
                if !finished { PhotoReminder.snooze(userId: member.id) }
                onClose()
            }
        ) {
            VStack(spacing: DS.Spacing.md) {
                ring
                Text(L10n.t("تظهر صورتك في الشجرة، وتساعد أفراد العائلة على التعرّف عليك.",
                            "Your photo appears in the tree and helps family recognize you."))
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

    private var ring: some View {
        ZStack {
            if let newImage {
                Image(uiImage: newImage).resizable().scaledToFill()
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
                onClose()
            case .sentForApproval:
                // لا صورة بعد حتى توافق الإدارة — لا يرجع التذكير قبل مدته
                PhotoReminder.snooze(userId: member.id)
                resultMessage = result.message
                finished = true
            case .failed:
                newImage = nil
                resultMessage = result.message
            }
        }
    }
}
