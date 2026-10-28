import SwiftUI
import PhotosUI
import Supabase

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Binding var selectedTab: Int
    @State private var showingNotifications = false
    @ObservedObject private var langManager = LanguageManager.shared

    @State private var showEditProfile = false
    /// معاينة الصورة مكبّرة (طلب المالك)
    @State private var showAvatarPreview = false
    @State private var showQRCode = false
    @State private var showQRScanner = false
    @State private var showSignOutConfirm = false
    @State private var showSettings = false

    @State private var showAddChild = false
    @State private var editingChild: FamilyMember? = nil
    @State private var editingFamilyMember: WomenFamilyEntry? = nil
    @State private var isReorderingChildren = false
    /// ستر أسماء النساء (الأم/الزوجة/البنات) — مغبّشة افتراضياً، وهزّ الجهاز يبدّل
    /// الأسماء ظاهرة دائماً — أُزيل الإخفاء بهزّ الجهاز (طلب المالك)
    private let womenRevealed = true
    /// «تقليل الحركة» من إعدادات الجهاز (توصية أبل): بلا انزلاق لقائمة الترتيب
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // «إضافة زوجة» الواحدة (طلب المالك ٢٠٢٦-١٠-٢٥): من أين هي؟ عند الخانة نفسها — من خارج العائلة بالاسم هناك،
    // ومن العائلة مربّع «أبوها ← بناته» المشترك مع شجرة النساء
    @State private var showWifeSource = false
    @State private var showWifeFamily = false
    @State private var showMotherOptions = false
    @State private var fatherWives: [WomanMember] = []
    /// الأم من بنات الشجرة (أبوها في الشجرة) أو إضافة أخت — مربّع بخطوتين (طلب المالك ٢٠٢٦-١٠-٢٤)
    @State private var showMotherFamily = false
    @State private var treeDaughterDoneMessage: String? = nil
    @State private var appeared = false
    @State private var isLoadingChildren = true
    /// الطلب المُختار للإلغاء — يشغّل حوار تأكيد السحب في «طلباتي».
    @State private var requestToCancel: AdminRequest? = nil
    /// سحب الطلب فشل — الرسالة من adminRequestVM
    @State private var cancelRequestError: String? = nil
    /// «مسار الموافقات»: تأكيد «وصل ردّك للإدارة» بعد الرد من «طلباتي»
    @State private var showApprovalReplySent = false
    /// حساب امرأة (دخول النساء ٢٠٢٦-١٠-٢٤): شجرة النساء لعقدتها وأمها وزوجها وأبنائها
    @State private var womenRows: [FamilyMember] = WomenStore.cache
    @State private var womenLoaded = !WomenStore.cache.isEmpty
    /// قريب من شجرة الرجال (الأب، الزوج، الابن) — يفتح تفاصيله
    @State private var relativeDetails: FamilyMember? = nil
    @Environment(\.verticalSizeClass) private var vSizeClass
    /// الوضع الأفقي — الأقسام تتوزع على عمودين
    private var isLandscape: Bool { vSizeClass == .compact }

    var user: FamilyMember? { authVM.currentUser }

    /// عائلة شجرة النساء (الأم/الزوجة/الأبناء) تظهر فقط عند «متزوج».
    private var isCurrentUserMarried: Bool { authVM.currentUser?.isMarried ?? false }
    private var hasWife: Bool { memberVM.currentMemberWomenFamily.contains { $0.role == .wife } }
    /// له أسرة: متزوج أو له زوجة/أبناء مسجّلون — خانات الزوجة والأبناء. الأم تظهر للجميع (قرار المالك ٢٠٢٦-١٠-٢٧)
    private var hasOwnFamily: Bool { isCurrentUserMarried || hasWife || !memberVM.currentMemberChildren.isEmpty }
    private var hasMother: Bool { memberVM.currentMemberWomenFamily.contains { $0.role == .mother } }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if let currentUser = user {
                    VStack(spacing: 0) {
                        MainHeaderView(
                            selectedTab: $selectedTab,
                            showingNotifications: $showingNotifications,
                            title: L10n.t("حسابي", "My Profile"),
                            subtitle: L10n.t("الملف الشخصي والإعدادات", "Profile and settings"),
                            icon: "person.fill",
                            section: .profile,
                            hideNotificationBell: true
                        ) {
                            // زر الإعدادات — يفتح كل تفضيلات التطبيق
                            // عارٍ بلا قرص وبحجم الجرس — نفس معالجة زرّ
                            // الإشعارات في الرئيسية، فيتّسق زرّا الهيدر.
                            DSIconButton(icon: "gearshape.fill",
                                         iconSize: 22,
                                         iconColor: DS.Color.headerGlyph,
                                         fillColor: .clear,
                                         borderColor: .clear) {
                                showSettings = true
                            }
                            .accessibilityLabel(L10n.t("الإعدادات", "Settings"))
                        }

                        ScrollView(showsIndicators: false) {
                            // دخول الأقسام تباعاً مرة عند الظهور — نمط الأخبار والديوانيات
                            // (طلب المالك ٢٠٢٦-٠٩-٢٧): الملف ← المعلومات ← طلباتي ← عائلتي ← الخروج.
                            // «المفضلة» أُزيلت (طلب المالك ٢٠٢٦-١٠-٠٧): لم يكن في التطبيق ما يضيف إليها
                            // «تقليل الحركة»: تلاشٍ فقط (داخل dsCardCascade)
                            Group {
                                if isLandscape {
                                    // الوضع الأفقي: عمودان — يمين (الملف + المعلومات) ويسار (الطلبات + العائلة)
                                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                                        VStack(spacing: DS.Spacing.md) {
                                            profileHeader(user: currentUser)
                                                .padding(.top, DS.Spacing.md)
                                                .dsCardCascade(0, appeared: appeared)
                                            personalInfoSection(user: currentUser)
                                                .dsCardCascade(1, appeared: appeared)
                                        }
                                        .frame(maxWidth: .infinity)

                                        VStack(spacing: DS.Spacing.md) {
                                            myRequestsSection
                                                .dsCardCascade(2, appeared: appeared)
                                            if isWomanAccount {
                                                womenPositionSection
                                                    .dsCardCascade(4, appeared: appeared)
                                            } else {
                                                serverSonsSection
                                                    .dsCardCascade(4, appeared: appeared)
                                            }
                                            signOutButton
                                                .dsCardCascade(5, appeared: appeared)
                                        }
                                        .padding(.top, DS.Spacing.md)
                                        .frame(maxWidth: .infinity)
                                    }
                                } else {
                                    VStack(spacing: DS.Spacing.md) {
                                        // Profile Header
                                        profileHeader(user: currentUser)
                                            .padding(.top, DS.Spacing.md)
                                            .dsCardCascade(0, appeared: appeared)

                                        // معلوماتي — وفيه صلة القرابة (طلب المالك ٢٠٢٦-١٠-٠٢)
                                        personalInfoSection(user: currentUser)
                                            .dsCardCascade(1, appeared: appeared)

                                        // طلباتي — الطلبات المعلّقة التي أرسلها العضو للإدارة
                                        myRequestsSection
                                            .dsCardCascade(2, appeared: appeared)

                                        // حساب امرأة: «موقعي في شجرة النساء» بدل «عائلتي» (روابطه من شجرة الرجال)
                                        if isWomanAccount {
                                            womenPositionSection
                                                .dsCardCascade(4, appeared: appeared)
                                        } else {
                                            // قسم «عائلتي» لكل رجل مفعّل — الأعزب يضيف أمّه (قرار المالك ٢٠٢٦-١٠-٢٧)
                                            serverSonsSection
                                                .dsCardCascade(4, appeared: appeared)
                                        }

                                        // زر تسجيل الخروج بأسفل الصفحة
                                        signOutButton
                                            .dsCardCascade(5, appeared: appeared)
                                    }
                                }
                            }
                            .padding(.bottom, DS.Spacing.xxl)
                            .dsTabBarClearance()   // أفقياً: آخر قسم لا يختفي تحت شريط التبويبات العائم
                            // «طلباتي» تصل بعد الظهور (جلب غير متزامن) أو تُسحب — القسم يظهر/يختفي بتلاشٍ
                            // وما تحته ينزاح بهدوء بدل القفز. «تقليل الحركة»: مباشرة كما كان
                            .animation(reduceMotion ? nil : DS.Anim.smooth,
                                       value: adminRequestVM.myPendingRequests.map(\.id))
                        } // closes ScrollView
                        .refreshable {
                            await memberVM.fetchAllMembers(force: true)
                            await memberVM.fetchChildren(for: currentUser.id)
                            await adminRequestVM.fetchMyPendingRequests(force: true)
                            if isWomanAccount { await loadWomenPosition() }
                        }
                        .task {
                            if isWomanAccount { await loadWomenPosition() }
                            isLoadingChildren = true
                            await memberVM.fetchChildren(for: currentUser.id)
                            isLoadingChildren = false
                            await adminRequestVM.fetchMyPendingRequests()
                        }
                        .onAppear {
                            // «مسار الموافقات»: المفتاح يُقرأ طازجاً كلما ظهر الملف (قد يتبدّل أثناء الجلسة)،
                            // و«طلباتي» تتحدّث (بمهلتها) — بلاغ المالك ٢٠٢٦-١٠-١٥: طلبه ظهر بلا شريط المسار
                            Task {
                                await adminRequestVM.refreshApprovalsFlag()
                                await adminRequestVM.fetchMyPendingRequests()
                            }
                            // الحركة نفسها داخل dsCardCascade (توقيت كل قسم + «تقليل الحركة»)
                            guard !appeared else { return }
                            appeared = true
                        }
                    } // closes VStack
                } else {
                    // التحميل الواحد: مجسّم القسم يتنفّس
                    DSPageLoader(L10n.t("جاري تحميل الملف...", "Loading profile..."))
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
                    .environment(\.layoutDirection, langManager.layoutDirection)
            }
            // نموذج طويل فيه كتابة وتمرير — مربّع طويل من الأسفل (توصية أبل)
            .dsTallBox(isPresented: $showEditProfile) {
                if let c = user { EditProfileView(member: c) }
            }
            .fullScreenCover(isPresented: $showAvatarPreview) {
                if let c = user {
                    AvatarPreview(member: c) {
                        showAvatarPreview = false
                    } onChangePhoto: { image in
                        await changeAvatar(image, for: c)
                    }
                    .background(ClearPresentationBackground())
                }
            }
            .transaction { t in
                // تظهر في مكانها بلا انزلاق من الأسفل
                if showAvatarPreview { t.disablesAnimations = true }
            }
            // رمز QR — مربّع عرض بمنتصف الشاشة بدل الورقة السفلية (طلب المالك)
            .dsCenterBox(isPresented: $showQRCode, onBackgroundTap: { showQRCode = false }) {
                if let c = user {
                    QRCodeSheet(member: c, selectedTab: $selectedTab)
                }
            }
            .fullScreenCover(isPresented: $showQRScanner) { QRScannerView(selectedTab: $selectedTab) }
            // إضافة/تعديل الأبناء مربّعات بمنتصف الشاشة بنفس تصميم الإضافة (طلب المالك)
            .fullScreenCover(isPresented: $showAddChild) {
                if let c = user {
                    DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { AddChildSheet(member: c) }
                        .background(ClearPresentationBackground())
                }
            }
            .transaction { t in if showAddChild { t.disablesAnimations = true } }
            // مربّع تسجيل الخروج بتصميم التطبيق الموحّد (طلب المالك ٢٠٢٦-١٠-٠٧ «نطوّره») بدل قائمة النظام —
            // مختصر: جملة واحدة، و«تسجيل الخروج» أحمر و«إلغاء»
            .dsAlert(L10n.t("تسجيل الخروج", "Sign Out"), isPresented: $showSignOutConfirm,
                     icon: "rectangle.portrait.and.arrow.right") {
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
                Button(L10n.t("تسجيل الخروج", "Sign Out"), role: .destructive) {
                    Task { await authVM.signOut() }
                }
            } message: {
                Text(L10n.t("سيتم تسجيل خروجك من هذا الجهاز.", "You'll be signed out on this device."))
            }
            // تأكيد سحب الطلب — مربّع التطبيق الموحّد بالمنتصف بدل القائمة السفلية
            .dsAlert(
                L10n.t("سحب الطلب", "Withdraw Request"),
                isPresented: Binding(
                    get: { requestToCancel != nil },
                    set: { if !$0 { requestToCancel = nil } }
                ),
                presenting: requestToCancel
            ) { request in
                Button(L10n.t("تراجع", "Keep"), role: .cancel) {}
                Button(L10n.t("سحب الطلب", "Withdraw"), role: .destructive) {
                    Task {
                        await adminRequestVM.cancelMyRequest(request)
                        // فشل السحب (عولج الطلب أو انقطاع) — الطلب رجع للقائمة، وتظهر الرسالة
                        if let message = adminRequestVM.errorMessage, !message.isEmpty {
                            cancelRequestError = message
                        }
                    }
                }
            } message: { _ in
                Text(L10n.t(
                    "سيتم إلغاء هذا الطلب ولن يصل للإدارة.",
                    "This request will be cancelled and won't be sent to the admins."
                ))
            }
            .dsAlert(
                L10n.t("خطأ", "Error"),
                isPresented: Binding(
                    get: { cancelRequestError != nil },
                    set: { if !$0 { cancelRequestError = nil } }
                )
            ) {
                Button(L10n.t("حسناً", "OK")) { cancelRequestError = nil }
            } message: {
                Text(cancelRequestError ?? "")
            }
            // «مسار الموافقات»: تأكيد وصول ردّ العضو للإدارة (الرد نفسه داخل «طلباتي»)
            .dsAlert(L10n.t("تم إرسال ردّك", "Reply sent"), isPresented: $showApprovalReplySent, moment: .sentForApproval) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(L10n.t("وصل ردّك للإدارة، ويكمل طلبك مراجعته.",
                            "Your reply reached the administration, and your request continues its review."))
            }
            .fullScreenCover(item: $editingChild) { child in
                DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { EditChildSheet(member: child) }
                    .background(ClearPresentationBackground())
            }
            .transaction { t in if editingChild != nil { t.disablesAnimations = true } }
            // حساب امرأة: الأب/الزوج/الابن من شجرة الرجال — نفس تفاصيل العضو
            .fullScreenCover(item: $relativeDetails) { m in
                MemberDetailsView(member: m, centered: true)
                    .background(ClearPresentationBackground())
            }
            .transaction { t in if relativeDetails != nil { t.disablesAnimations = true } }
            // تعديل فرد من «عائلتي» — مربّع بمنتصف الشاشة بتصميم مربّعات الإضافة (طلب المالك)
            .dsCenterBox(item: $editingFamilyMember) { entry in
                WomanMemberEditSheet(memberVM: memberVM, entry: entry,
                                     canEditGender: authVM.canEditMembers)
            }
            // «إضافة زوجة» من العائلة: أبوها من الشجرة ← بناته المتاحات (لا متزوجة ولا دون ١٨ ولا مولودة حديثاً)
            // أو تُضاف تحته — نفس مربّع شجرة النساء (`DSWifeFlowBox`) ودالة السيرفر الذاتية
            .dsCenterBox(isPresented: $showWifeFamily) {
                if let me = user {
                    ProfileWifeFamilyBox(
                        memberVM: memberVM, me: me,
                        onFatherMissing: { typed in
                            showWifeFamily = false
                            requestMissingFather(typed, me: me, relation: .wife)
                        },
                        onDone: { message in
                            showWifeFamily = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { treeDaughterDoneMessage = message }
                        },
                        onCancel: { showWifeFamily = false }
                    )
                }
            }
            // «الأم من العائلة» — نفس مربّع الزوجة (طلب المالك ٢٠٢٦-١٠-٢٥ «الأم نفس طريقة الزوجة»)
            .dsCenterBox(isPresented: $showMotherFamily) {
                if let me = user {
                    ProfileWifeFamilyBox(
                        memberVM: memberVM, me: me, relation: .mother,
                        onFatherMissing: { typed in
                            showMotherFamily = false
                            requestMissingFather(typed, me: me, relation: .mother)
                        },
                        onDone: { message in
                            showMotherFamily = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { treeDaughterDoneMessage = message }
                        },
                        onCancel: { showMotherFamily = false }
                    )
                }
            }
            .dsAlert(
                L10n.t("تم", "Done"),
                isPresented: Binding(
                    get: { treeDaughterDoneMessage != nil },
                    set: { if !$0 { treeDaughterDoneMessage = nil } }
                )
            ) {
                Button(L10n.t("حسناً", "OK")) { treeDaughterDoneMessage = nil }
            } message: {
                Text(treeDaughterDoneMessage ?? "")
            }
            .onChange(of: showAddChild) { isPresented in
                guard !isPresented, let currentUser = user else { return }
                Task {
                    await memberVM.fetchChildren(for: currentUser.id)
                    // إضافة ابن تُنشئ طلب موافقة → حدّث «طلباتي»
                    await adminRequestVM.fetchMyPendingRequests(force: true)
                }
            }
            .onChange(of: editingChild) { newValue in
                guard newValue == nil, let currentUser = user else { return }
                Task { await memberVM.fetchChildren(for: currentUser.id) }
            }
            .onChange(of: showEditProfile) { isPresented in
                // إغلاق «تعديل البيانات» قد يعني إرسال طلب رقم/وفاة/اسم → حدّث «طلباتي»
                guard !isPresented else { return }
                Task { await adminRequestVM.fetchMyPendingRequests(force: true) }
            }

        }
        .environment(\.layoutDirection, langManager.layoutDirection)
    }

    /// تغيير الصورة من المعاينة (طلب المالك): أول ٣ تغييرات تُرفع مباشرة،
    /// وبعدها تُرسل اقتراحاً للإدارة — نفس قاعدة شاشة تعديل البيانات.
    /// يرجّع رسالة النتيجة لتُعرض داخل المعاينة.
    @MainActor
    private func changeAvatar(_ image: UIImage, for member: FamilyMember) async -> String {
        let cooldown = ProfileEditCooldown.shared
        if cooldown.canEdit(.avatar) {
            let uploaded = await memberVM.uploadAvatar(image: image, for: member.id)
            guard uploaded else {
                return L10n.t("تعذّر رفع الصورة. حاول مرة ثانية.", "Couldn't upload the photo. Try again.")
            }
            cooldown.recordEdit(.avatar)
            return L10n.t("تم تغيير الصورة", "Photo changed")
        }
        guard let url = await adminRequestVM.uploadPhotoSuggestion(image) else {
            return L10n.t("تعذّر رفع الصورة. حاول مرة ثانية.", "Couldn't upload the photo. Try again.")
        }
        let ok = await adminRequestVM.submitTreeEditRequest(payload: .make(
            action: .addPhoto,
            targetMemberId: member.id.uuidString,
            targetMemberName: member.fullName,
            newPhotoUrl: url,
            notes: L10n.t("تعديل صورة بعد تجاوز حد التعديلات", "Photo edit after reaching the edit limit")
        ))
        return ok
            ? L10n.t("تجاوزت ٣ تغييرات — أُرسلت الصورة للإدارة للموافقة", "Over 3 changes — sent to the admins for approval")
            : L10n.t("تعذّر إرسال الطلب. حاول مرة ثانية.", "Couldn't send the request. Try again.")
    }

    // MARK: - Profile Header — Avatar & Info
    private func profileHeader(user: FamilyMember) -> some View {
        VStack(spacing: 0) {
            // الصورة الشخصية
            ZStack {
                // حلقة خارجية متوهجة
                Circle()
                    .fill(DS.Color.surface)
                    .frame(width: DS.Icon.profileAvatarRing, height: DS.Icon.profileAvatarRing)
                    .dsGlowShadow()
                
                // حلقة بلون واحد (الهوية: بلا تدرّج) — بلون تبويب «حسابي»
                Circle()
                    .stroke(AppSection.profile.ink, lineWidth: DS.Border.widthBold * 2)
                    .frame(width: DS.Icon.profileAvatarRing - DS.Spacing.xs,
                           height: DS.Icon.profileAvatarRing - DS.Spacing.xs)

                if let urlStr = user.avatarUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                    placeholder: { AppSection.profile.ink.opacity(DS.Opacity.tintFill) }
                    .frame(width: DS.Icon.profileAvatar, height: DS.Icon.profileAvatar).clipShape(Circle())
                } else {
                    Circle()
                        .fill(DS.Color.background)
                        .frame(width: DS.Icon.profileAvatar, height: DS.Icon.profileAvatar)
                        .overlay(
                            Text(String(user.firstName.first ?? "P"))
                                .dsFont(.avatarInitial)
                                .foregroundColor(AppSection.profile.ink)
                        )
                }
            }
            .contentShape(Circle())
            .onTapGesture { showAvatarPreview = true }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(L10n.t("معاينة الصورة", "Preview photo"))
            .padding(.top, DS.Spacing.xl)
            
            // User Info
            VStack(spacing: DS.Spacing.sm) {
                Button { showEditProfile = true } label: {
                    // سطر واحد إن وسع، وإلا سطران متوازنان (`DSBalanced`) — القلم ملتصق بآخر الاسم
                    let name = user.fullName.isEmpty ? L10n.t("غير معروف", "Unknown") : user.displayFullName
                    ViewThatFits(in: .horizontal) {
                        profileNameLine(name).lineLimit(1)
                        profileNameLine(DSBalanced.twoLines(name)).lineLimit(2)
                    }
                    .multilineTextAlignment(.center)
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("تعديل البيانات", "Edit Profile"))
                .padding(.horizontal, DS.Spacing.lg)

                // مستوى الحساب + عدد الأبناء
                HStack(spacing: DS.Spacing.sm) {
                    // الرتبة — كبسولة الحالة المشتركة
                    DSStatusChip(text: user.roleName, icon: "circle.fill", tint: user.roleColor)

                    // عدد الأبناء (شجرة الرجال + شجرة النساء)
                    // الأبناء الذكور لهم نسخة في شجرة النساء — نستثنيها حتى لا يُحسب
                    // الابن مرتين عند الأعضاء المتزوجين (طلب المالك)
                    let totalChildren = memberVM.currentMemberChildren.count + memberVM.currentMemberWomenFamily.filter { $0.role != .child || $0.member.gender != "male" }.count
                    if totalChildren > 0 {
                        DSStatusChip(text: "\(totalChildren) " + L10n.t("من العائلة", "family"),
                                     icon: "person.2.fill", tint: DS.Color.textSecondary)
                            // العدد يتبدّل بلفّة أرقام حين يُضاف فرد — «تقليل الحركة»: مباشرة
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : DS.Anim.smooth, value: totalChildren)
                    }
                }
            }
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)
        }
    }

    // MARK: - Personal Info Section
    private func personalInfoSection(user: FamilyMember) -> some View {
        let infoItems = buildInfoItems(user: user)
        let columns = [GridItem(.flexible()), GridItem(.flexible())]

        // «معلوماتي» — بطاقة القسم الواحدة، وزرّا الرمز (للقرابة) شريحتان بطرف العنوان (طلب المالك ٢٠٢٦-١٠-٠٢)
        return DSFormCard(L10n.t("معلوماتي", "My info"), icon: "person.text.rectangle.fill",
                          color: DS.Color.primary) {
            HStack(spacing: DS.Spacing.sm) {
                DSChipButton(L10n.t("مسح رمز", "Scan"), icon: "camera.viewfinder",
                             tint: DS.Color.accent, size: .mini) { showQRScanner = true }
                    .accessibilityLabel(L10n.t("مسح رمز QR", "Scan QR Code"))
                DSChipButton(L10n.t("رمزي", "My code"), icon: "qrcode",
                             tint: DS.Color.secondary, size: .mini) { showQRCode = true }
                    .accessibilityLabel(L10n.t("عرض رمز QR", "Show QR Code"))
            }
        } content: {
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                ForEach(infoItems, id: \.title) { item in
                    infoGridCell(icon: item.icon, color: item.color, title: item.title, value: item.value)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private struct InfoItem {
        let icon: String
        let color: Color
        let title: String
        let value: String
    }

    private func buildInfoItems(user: FamilyMember) -> [InfoItem] {
        var items: [InfoItem] = []

        items.append(InfoItem(
            icon: "phone.fill",
            color: DS.Color.textSecondary,
            title: L10n.t("الهاتف", "Phone"),
            value: user.phoneNumber.flatMap { $0.isEmpty ? nil : KuwaitPhone.display($0) } ?? L10n.t("غير محدد", "N/A")
        ))

        if let birth = user.birthDate, !birth.isEmpty {
            items.append(InfoItem(
                icon: "calendar",
                color: DS.Color.textSecondary,
                title: L10n.t("تاريخ الميلاد", "Birthday"),
                value: birth
            ))
        }

        if let married = user.isMarried {
            items.append(InfoItem(
                icon: "heart.fill",
                color: DS.Color.textSecondary,
                title: L10n.t("الحالة الاجتماعية", "Status"),
                value: user.isWomanAccount
                    ? (married ? L10n.t("متزوجة", "Married") : L10n.t("عزباء", "Single"))
                    : (married ? L10n.t("متزوج", "Married") : L10n.t("أعزب", "Single"))
            ))
        }

        if let created = user.createdAt, !created.isEmpty {
            items.append(InfoItem(
                icon: "clock.fill",
                color: DS.Color.textSecondary,
                title: L10n.t("تاريخ الانضمام", "Joined"),
                value: formatDateOnly(created)
            ))
        }

        return items
    }

    private func infoGridCell(icon: String, color: Color, title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            DSStateIcon(icon, tint: color, size: DS.Icon.rowLarge)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)

                Text(value)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .profileCell()
    }

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private func formatDateOnly(_ dateString: String) -> String {
        guard let date = Self.isoDateFormatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString) else {
            return dateString
        }
        Self.displayDateFormatter.locale = LanguageManager.shared.locale
        return Self.displayDateFormatter.string(from: date)
    }

    // MARK: - موقعي في شجرة النساء (حساب امرأة — دخول النساء ٢٠٢٦-١٠-٢٤)
    // حسابها صفّ في `profiles` مخفيّ بلا أب؛ موقعها عقدتها في `women_members` (`linked_user_id` = معرّفها).
    // روابط «عائلتي» (أم/زوجة/أبناء profiles ودوال `*_self_*`) للرجال — لا تُعرض لها؛ التصحيح بطلب للإدارة.

    private var isWomanAccount: Bool { user?.isWomanAccount ?? false }

    /// عقدتها في شجرة النساء — من آخر جلب
    private var myWomanNode: FamilyMember? {
        guard let me = user, let womanId = WomenStore.womanByLinkedUser[me.id] else { return nil }
        return womenRows.first { $0.id == womanId }
    }

    private func loadWomenPosition() async {
        do {
            womenRows = try await WomenStore.fetch()
        } catch {
            Log.warning("[Women] تعذّر جلب موقع الحساب في شجرة النساء: \(error.localizedDescription)")
        }
        womenLoaded = true
    }

    private var womenPositionSection: some View {
        DSFormCard(L10n.t("موقعي في شجرة النساء", "My place in the women tree"),
                   icon: "figure.stand.dress", color: DS.Color.female) {
            if let node = myWomanNode {
                womenPositionContent(node)
            } else if !womenLoaded {
                DSPageLoader(fillsSpace: false)
                    .padding(.vertical, DS.Spacing.sm)
            } else {
                DSNoteCard(L10n.t("حسابك غير مربوط بشجرة النساء بعد — تربطك الإدارة.",
                                  "Your account isn't linked to the women tree yet — the administration will link you."),
                           icon: "link")
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private func womenPositionContent(_ node: FamilyMember) -> some View {
        let byId = Dictionary(womenRows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // الأب والزوج والأبناء الذكور لهم نفس المعرّف في شجرة الرجال — تفتح تفاصيلهم
        let fatherProfile = node.fatherId.flatMap { memberVM.member(byId: $0) }
        let fatherName = fatherProfile?.displayFullName ?? node.fatherId.flatMap { byId[$0]?.fullName }
        let mother = node.motherId.flatMap { byId[$0] }
        let husband = node.husbandId.flatMap { byId[$0] }
        let husbandProfile = node.husbandId.flatMap { memberVM.member(byId: $0) }
        let children = womenRows
            .filter { $0.id != node.id && ($0.motherId == node.id || $0.fatherId == node.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(node.fullName.isEmpty ? node.firstName : node.fullName)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let fatherName, !fatherName.isEmpty {
                womanRelationRow(icon: "person.fill", tint: DS.Color.male, title: L10n.t("الأب", "Father"),
                                 name: fatherName, open: fatherProfile)
            }
            if let mother {
                womanRelationRow(icon: "figure.stand.dress", tint: DS.Color.female, title: L10n.t("الأم", "Mother"),
                                 name: mother.fullName.isEmpty ? mother.firstName : mother.fullName, open: nil)
            }
            if let husband {
                womanRelationRow(icon: "heart.fill", tint: DS.Color.male, title: L10n.t("الزوج", "Husband"),
                                 name: husbandProfile?.displayFullName ?? husband.fullName, open: husbandProfile)
            }
            ForEach(children, id: \.id) { child in
                womanRelationRow(icon: child.isFemale ? "figure.stand.dress" : "person.fill",
                                 tint: child.isFemale ? DS.Color.female : DS.Color.male,
                                 title: child.isFemale ? L10n.t("ابنة", "Daughter") : L10n.t("ابن", "Son"),
                                 name: child.firstName.isEmpty ? child.fullName : child.firstName,
                                 open: child.isFemale ? nil : memberVM.member(byId: child.id))
            }
            DSButton(L10n.t("عرض في شجرة النساء", "Show in the women tree"), icon: "location.fill") {
                openMyWomenNode()
            }
        }
    }

    /// صفّ قرابة — يفتح تفاصيل العضو إن كان من شجرة الرجال
    @ViewBuilder
    private func womanRelationRow(icon: String, tint: Color, title: String, name: String,
                                  open member: FamilyMember?) -> some View {
        if let member {
            Button { relativeDetails = member } label: {
                DSRow(icon: icon, tint: tint, title: title, subtitle: name) { DSChevron() }
            }
            .buttonStyle(DSPressStyle())
        } else {
            DSRow(icon: icon, tint: tint, title: title, subtitle: name)
        }
    }

    /// تبويب الشجرة ← النساء متمركزة على عقدتها (`WomenClassicTreeView.autoLocate`)
    private func openMyWomenNode() {
        TreeTabContainer.openWomenOnAppear = true
        NotificationCenter.default.post(name: .openWomenTree, object: nil)
    }

    // MARK: - Children Section
    // MARK: - طلباتي (My Requests)

    /// الطلبات المعلّقة التي أرسلها العضو للإدارة — عرض + متابعة + سحب.
    @ViewBuilder
    private var myRequestsSection: some View {
        let requests = adminRequestVM.myPendingRequests
        if !requests.isEmpty {
            DSFormCard(L10n.t("طلباتي", "My Requests"), icon: "clock.badge.exclamationmark.fill",
                       color: DS.Color.warning) {
                Text("\(requests.count)")
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            } content: {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(requests, id: \.id) { request in
                        myRequestRow(request)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    /// المسار شغّال (أو الطلب نفسه يحمل مرحلة من السيرفر) → صفّ بمرحلة الطلب ومتتبّعه (وما تطلبه الإدارة)،
    /// وإلا الصفّ كما كان
    @ViewBuilder
    private func myRequestRow(_ request: AdminRequest) -> some View {
        if let flow = adminRequestVM.memberApprovalSnapshot(for: request) {
            myApprovalRequestRow(request, flow: flow)
        } else {
            myClassicRequestRow(request)
        }
    }

    /// «مسار الموافقات» (طلب المالك ٢٠٢٦-١٠-١٥): العنوان وشارة المرحلة ← متتبّع الخطوات ← وإن طلبت
    /// الإدارة معلومات: ما تطلبه وحقل لكل مطلوب و«إرسال للإدارة» — العضو يُخاطَب بـ«الإدارة» لا بالأدوار
    private func myApprovalRequestRow(_ request: AdminRequest, flow: ApprovalSnapshot) -> some View {
        let info = myRequestDisplay(for: request)
        return VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                DSStateIcon(info.icon, tint: info.color, size: DS.Icon.rowLarge)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(info.title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(1)
                    if let target = info.target, !target.isEmpty {
                        Text(target)
                            .dsFont(.subtitle)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    ApprovalStageChips(snapshot: flow, audience: .member)
                }

                Spacer(minLength: DS.Spacing.sm)

                DSChipButton(L10n.t("سحب", "Withdraw"), tint: DS.Color.error, size: .small) { requestToCancel = request }
                    .accessibilityLabel(L10n.t("سحب الطلب", "Withdraw request"))
            }

            ApprovalTracker(stage: flow.stage, audience: .member)

            if flow.stage == .info {
                ApprovalMemberReplyCard(adminRequestVM: adminRequestVM, snapshot: flow) {
                    showApprovalReplySent = true
                }
                // سؤال جديد = مسودة جديدة (لا تبقى قيم ردّ سابق)
                .id("\(flow.requestId)-\(flow.stageSince?.timeIntervalSince1970 ?? 0)")
            }
        }
        .profileCell()
    }

    private func myClassicRequestRow(_ request: AdminRequest) -> some View {
        let info = myRequestDisplay(for: request)
        return HStack(spacing: DS.Spacing.md) {
            DSStateIcon(info.icon, tint: info.color, size: DS.Icon.rowLarge)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(info.title)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if let target = info.target, !target.isEmpty {
                    Text(target)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                        .lineLimit(1)
                }

                // شارة «تحت المراجعة» — كبسولة الحالة المشتركة
                DSStatusChip(text: L10n.t("تحت المراجعة", "Under Review"),
                             icon: "clock.badge.questionmark", tint: DS.Color.warning)
            }

            Spacer(minLength: DS.Spacing.sm)

            // سحب/إلغاء الطلب — الشريحة الواحدة بلون الحذف
            DSChipButton(L10n.t("سحب", "Withdraw"), tint: DS.Color.error, size: .small) { requestToCancel = request }
                .accessibilityLabel(L10n.t("سحب الطلب", "Withdraw request"))
        }
        .profileCell()
    }

    private struct MyRequestDisplay {
        let icon: String
        let color: Color
        let title: String
        let target: String?
    }

    /// يشتق أيقونة/لون/عنوان/هدف الطلب حسب نوعه للعرض في «طلباتي».
    private func myRequestDisplay(for request: AdminRequest) -> MyRequestDisplay {
        let selfId = authVM.currentUser?.id
        // اسم العضو المستهدف — نُخفيه إن كان العضو نفسه (زائد بلا فائدة)
        let targetName: String? = {
            guard let m = request.member, m.id != selfId else { return nil }
            return m.displayFullName
        }()

        switch request.requestType {
        case RequestType.treeEdit.rawValue:
            let action = request.treeEditPayload?.resolvedAction
            let name = memberVM.treeEditTargetName(request.treeEditPayload)
                ?? request.treeEditPayload?.newMemberName
                ?? targetName
            return MyRequestDisplay(
                icon: action?.iconName ?? "square.and.pencil",
                color: treeEditColor(for: action),
                title: L10n.t(action?.arabicLabel ?? "طلب تعديل", action?.englishLabel ?? "Edit request"),
                target: name
            )
        case RequestType.nameChange.rawValue:
            return .init(icon: "pencil.line", color: DS.Color.info,
                         title: L10n.t("تغيير الاسم", "Name change"),
                         target: request.newValue ?? targetName)
        case RequestType.phoneChange.rawValue:
            return .init(icon: "phone.arrow.up.right", color: AppSection.profile.ink,
                         title: L10n.t("تغيير رقم الهاتف", "Phone change"), target: targetName)
        case RequestType.deceasedReport.rawValue:
            return .init(icon: "heart.slash", color: DS.Color.textTertiary,
                         title: L10n.t("تسجيل وفاة", "Deceased report"), target: targetName)
        case RequestType.childAdd.rawValue:
            return .init(icon: "person.badge.plus", color: DS.Color.palm,
                         title: L10n.t("إضافة ابن", "Add child"), target: targetName)
        // أنواع تظهر في «طلباتي» والمسار شغّال فقط (ليُرد على سؤال المختص)
        case RequestType.familyChange.rawValue:
            return .init(icon: "person.2.fill", color: DS.Color.info,
                         title: L10n.t("تغيير العائلة", "Family change"), target: request.newValue ?? targetName)
        case RequestType.photoSuggestion.rawValue:
            return .init(icon: "camera.badge.ellipsis", color: AppSection.profile.ink,
                         title: L10n.t("اقتراح صورة", "Photo suggestion"), target: targetName)
        case RequestType.newsReport.rawValue, RequestType.contentReport.rawValue:
            return .init(icon: "exclamationmark.bubble.fill", color: DS.Color.error,
                         title: L10n.t("بلاغ", "Report"), target: nil)
        default:
            return .init(icon: "clock", color: DS.Color.warning,
                         title: L10n.t("طلب", "Request"), target: targetName)
        }
    }

    private func treeEditColor(for action: TreeEditAction?) -> Color {
        switch action {
        case .add: return DS.Color.palm
        case .editName: return DS.Color.info
        case .editPhone: return AppSection.profile.ink
        case .editBirth: return DS.Color.palm
        case .deceased, .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return AppSection.profile.ink
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        case .none: return DS.Color.warning
        }
    }

    /// يمكن ترتيب الأبناء (شجرة الرجال — profiles) لأي عضو لعائلته نفسه.
    private var canReorderSons: Bool { memberVM.currentMemberChildren.count > 1 }
    /// ترتيب البنات (شجرة النساء — women_members) مقيّد على الإدارة حسب RLS.
    private var canReorderDaughters: Bool { womenChildrenList.count > 1 }   // self-service عبر RPC مقيّد على النفس
    /// هل يوجد ما يمكن لهذا العضو ترتيبه فعلاً؟ (يتحكم بظهور زر «ترتيب» ووضع الترتيب)
    private var canReorderChildren: Bool { canReorderSons || canReorderDaughters }

    private var serverSonsSection: some View {
        // «عائلتي» — بطاقة القسم الواحدة، و«ترتيب/تم» شريحة بطرف العنوان
        DSFormCard(L10n.t("عائلتي", "My Family"), icon: "person.2.fill", color: DS.Color.textSecondary) {
            if canReorderChildren {
                DSChipButton(isReorderingChildren ? L10n.t("تم", "Done") : L10n.t("ترتيب", "Sort"),
                             icon: isReorderingChildren ? "checkmark" : "arrow.up.arrow.down",
                             tint: isReorderingChildren ? DS.Color.success : DS.Color.primary,
                             isSelected: isReorderingChildren, size: .small) {
                    withAnimation(DS.Anim.snappy) {
                        isReorderingChildren.toggle()
                    }
                }
            }
        } content: {
            if isLoadingChildren && memberVM.currentMemberChildren.isEmpty {
                // التحميل الواحد: مجسّم القسم يتنفّس (بدل صفوف الهيكل الرمادية)
                DSPageLoader(fillsSpace: false)
                    .padding(.vertical, DS.Spacing.sm)
                    .transition(.opacity)
            } else if isReorderingChildren && canReorderChildren {
                // وضع ترتيب موحّد — الأبناء (وللإدارة: البنات أيضاً) في قائمة واحدة
                childrenReorderView
            } else {
                // الوضع العادي — شبكة قابلة للنقر للتعديل
                childrenGridView
                    .transition(.opacity)
            }
        }
        .animation(DS.Anim.medium, value: isLoadingChildren)
        .padding(.horizontal, DS.Spacing.lg)
    }

    // MARK: - Grid View (الوضع العادي)
    /// خلية إجراء إضافة (زوجة/أم) بنفس شكل خلية «إضافة ابن».
    private func addFamilyActionCell(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.sm) {
                DSStateIcon(icon, tint: color, size: DS.Icon.rowLarge)
                    .accessibilityHidden(true)   // زخرفة — العنوان يكفي للقارئ الصوتي
                Text(title).dsFont(.chip).foregroundColor(color.dsReadableGlyph)
                    // سطران مع الخط الكبير بدل «…» (مقاسات Apple، ٢٠٢٦-١٠-٠٨)
                    .lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
            }
            // خانة إضافة: صندوق الصفوف بإطار متقطّع بلونها (نفس خانات «+» المشتركة)
            .profileCell(dashed: color)
        }
        .buttonStyle(DSPressStyle())   // ضغطة ناعمة موحّدة (كانت بلا أي إحساس بالضغط)
    }

    /// خلية فرد عائلة (أم/زوجة/ابنة) — قابلة للنقر لأي عضو لإدارة عائلته نفسه.
    /// إجراءات الإضافة/الإزالة داخل الورقة مقيّدة على النفس (RPCs)، والتعديل المباشر
    /// يظهر خطأً واضحاً إن رفضته RLS — لا صمت.
    private func familyMemberButton(_ entry: WomenFamilyEntry) -> some View {
        Button { editingFamilyMember = entry } label: { womanFamilyGridCell(entry: entry) }
            .buttonStyle(DSPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(familyMemberAccessibilityLabel(entry))
            .accessibilityHint(L10n.t("تعديل", "Edit"))
    }

    /// «من أين الزوجة؟» + الإضافة بالاسم في مربّع عند الخانة نفسها (طلب المالك)
    private func wifeSourcePopover<V: View>(_ anchor: V, editing wife: WomenFamilyEntry? = nil) -> some View {
        anchor.anchoredPopover(isPresented: $showWifeSource) {
            WifeSourceCard(
                onFamily: {
                    showWifeSource = false
                    // المربّع يُفتح فوراً ويحمّل بداخله
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showWifeFamily = true }
                },
                onAdd: { name, hidden in
                    let ok = await memberVM.addSelfWife(name: name, hidden: hidden)
                    if ok { showWifeSource = false; return nil }
                    return memberVM.errorMessage ?? L10n.t("تعذّرت الإضافة.", "Couldn't add.")
                },
                onCancel: { showWifeSource = false },
                onEdit: wife.map { w in {
                    showWifeSource = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { editingFamilyMember = w }
                } }
            )
        }
    }

    /// القارئ الصوتي: الاسم + الدور (أم/زوجة) + «متوفى» — نفس ما تعرضه الخلية
    private func familyMemberAccessibilityLabel(_ entry: WomenFamilyEntry) -> String {
        var parts = [entry.member.firstName.isEmpty ? L10n.t("فرد", "Member") : entry.member.firstName]
        if entry.role != .child { parts.append(L10n.t(entry.role.label, entry.role.labelEn)) }
        if entry.member.isDeceased { parts.append(L10n.t("متوفى", "deceased")) }
        return parts.joined(separator: L10n.t("، ", ", "))
    }

    private var childrenGridView: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        let parents = memberVM.currentMemberWomenFamily.filter { $0.role == .mother || $0.role == .wife }
        let womenKids = womenOnlyChildren
        let motherEntry = parents.first { $0.role == .mother }
        let wifeEntries = parents.filter { $0.role == .wife }
        // صف الأم يظهر لكل عضو، والزوجة لمن له أسرة — الإضافة/الاختيار مقيّدة على النفس.
        let showParents = true
        return VStack(spacing: DS.Spacing.sm) {
            // ═══ الأم / الزوجة — أماكن ثابتة (البطاقة أو زر الإضافة/الاختيار) ═══
            if showParents {
                LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                    // خانة الأم (ثابتة أولاً)
                    if let motherEntry {
                        familyMemberButton(motherEntry)
                    } else {
                        // إضافة/اختيار الأم متاحة لأي عضو (set_self_mother/add_self_mother مقيّدة على النفس)
                        addFamilyActionCell(title: L10n.t("إضافة/اختيار الأم", "Add/Pick Mother"),
                                            icon: "person.fill", color: DS.Color.accent) {
                            Task { fatherWives = await memberVM.fetchFatherWives(); showMotherOptions = true }
                        }
                        // الاختيار/الإضافة في مربّع عند الخانة نفسها (طلب المالك)
                        .anchoredPopover(isPresented: $showMotherOptions) {
                            MotherPickCard(
                                wives: fatherWives,
                                onPick: { id in
                                    showMotherOptions = false
                                    Task { await memberVM.setSelfMother(motherId: id) }
                                },
                                onAdd: { name in
                                    showMotherOptions = false
                                    Task { await memberVM.addSelfMother(name: name) }
                                },
                                onTree: {
                                    showMotherOptions = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showMotherFamily = true }
                                },
                                onCancel: { showMotherOptions = false }
                            )
                        }
                    }
                    // خانة الزوجة (ثابتة بعد الأم) — آخر زوجة تفتح مربّع «إضافة زوجة» وفيه «تعديل» زوجتك
                    // (طلب المالك ٢٠٢٦-١٠-٢٨: «زوجة أخرى» بلا خانة مستقلة ولا «+»)
                    ForEach(wifeEntries) { entry in
                        if hasOwnFamily && entry.id == wifeEntries.last?.id {
                            wifeSourcePopover(
                                Button { showWifeSource = true } label: { womanFamilyGridCell(entry: entry) }
                                    .buttonStyle(DSPressStyle())
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(familyMemberAccessibilityLabel(entry)),
                                editing: entry)
                        } else {
                            familyMemberButton(entry)
                        }
                    }
                    // إضافة الزوجة الأولى لمن له أسرة — اختياري لا إجبار
                    if hasOwnFamily && wifeEntries.isEmpty {
                        wifeSourcePopover(addFamilyActionCell(title: L10n.t("إضافة زوجة", "Add Wife"),
                                                              icon: "heart.fill", color: DS.Color.neonPink) {
                            showWifeSource = true
                        })
                    }
                    // الأخت لا تظهر ولا تُضاف من «حسابي» — من الشجرة فقط، تحت الأب (طلب المالك ٢٠٢٦-١٠-٢٤)
                }
                DSDivider()
            }

            // ═══ الأبناء ═══
            LazyVGrid(columns: columns, spacing: DS.Spacing.md) {
                ForEach(memberVM.currentMemberChildren, id: \.id) { son in
                    Button { editingChild = son } label: { childGridCell(son: son) }
                        .buttonStyle(DSPressStyle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel((son.firstName.isEmpty ? L10n.t("ابن بدون اسم", "Unnamed child") : son.firstName)
                                            + ((son.isDeceased ?? false) ? L10n.t("، متوفى", ", deceased") : ""))
                        .accessibilityHint(L10n.t("تعديل", "Edit"))
                }
                // البنات — قابلة للنقر للتعديل لأي عضو؛ الترتيب انتقل للوضع الموحّد.
                ForEach(womenKids) { entry in
                    familyMemberButton(entry)
                }
                // إضافة ابن — نفس خانة الإضافة (لمن له أسرة)
                if hasOwnFamily {
                    addFamilyActionCell(title: L10n.t("إضافة ابن", "Add Child"), icon: "plus",
                                        color: AppSection.profile.ink) { showAddChild = true }
                }
            }
        }
    }

    private func childGridCell(son: FamilyMember) -> some View {
        let info = childIconInfo(for: son)

        return HStack(spacing: DS.Spacing.sm) {
            childAvatarView(for: son, iconFont: DS.Glyph.lg, size: DS.Icon.rowLarge)

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)

                if son.isDeceased ?? false {
                    DSStatusChip(text: L10n.t("متوفى", "Deceased"), tint: info.color, size: .mini)
                }
            }
        }
        .profileCell()
    }

    /// أبناء شجرة النساء بالترتيب الحالي (للترتيب).
    private var womenChildrenList: [WomanMember] {
        womenOnlyChildren.map { $0.member }
    }

    /// أبناء شجرة النساء بدون الأبناء الذكور المنسوخين لها بنفس المعرّف — كان الابن يظهر مرتين
    /// في «عائلتي» و«ترتيب» (مرة من الأبناء ومرة من شجرة النساء). طلب المالك ٢٠٢٦-١٠-١٥.
    /// والابن المنسوخ يُستبعد بجنسه أيضاً — لو لم تُحدَّث قائمة الأبناء بعد إضافته كان يظهر كابنة،
    /// وحذفه من هناك يحذف النسخة فقط ويبقى الابن (طلب المالك ٢٠٢٦-١٠-١٥ «علي حذفته ليش موجود»).
    private var womenOnlyChildren: [WomenFamilyEntry] {
        let sonIds = Set(memberVM.currentMemberChildren.map(\.id))
        return memberVM.currentMemberWomenFamily.filter {
            $0.role == .child && !sonIds.contains($0.member.id) && $0.member.gender != "male"
        }
    }

    /// نقل ابن/ابنة أعلى/أسفل في الترتيب.
    private func moveWomanChild(_ child: WomanMember, up: Bool) {
        var list = womenChildrenList
        guard let idx = list.firstIndex(where: { $0.id == child.id }) else { return }
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < list.count else { return }
        list.swapAt(idx, target)
        Task { await memberVM.reorderSelfWomenChildren(list.map { $0.id }) }
    }

    // خلية فرد «عائلتي» — بنفس شكل خلايا الأبناء القديمة (صورة + اسم)، دور رمادي خفيف.
    private func womanFamilyGridCell(entry: WomenFamilyEntry) -> some View {
        let woman = entry.member
        return HStack(spacing: DS.Spacing.sm) {
            Group {
                if let urlStr = woman.displayImageUrl, let url = URL(string: urlStr) {
                    CachedAsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: { womanAvatarFallback }
                } else {
                    womanAvatarFallback
                }
            }
            .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(AppSection.profile.ink.opacity(DS.Opacity.tintFill), lineWidth: DS.Border.width))

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                // الاسم وحده هو المستور — الصورة والدور يبقيان ظاهرين
                Text(woman.firstName.isEmpty ? L10n.t("الاسم", "Name") : woman.firstName)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                    .blur(radius: womenRevealed ? 0 : 5)

                HStack(spacing: DS.Spacing.xs) {
                    // الدور (زوجة/أم) — يُخفى للأبناء
                    if entry.role != .child {
                        Text(L10n.t(entry.role.label, entry.role.labelEn))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .lineLimit(1)
                    }
                    if woman.isDeceased {
                        DSStatusChip(text: L10n.t("متوفى", "Deceased"), tint: DS.Color.error, size: .mini)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .profileCell()
    }

    private var womanAvatarFallback: some View {
        ZStack {
            AppSection.profile.ink.opacity(DS.Opacity.tintFillSoft)
            Image(systemName: "person.fill")
                .dsGlyph(DS.Glyph.lg)
                .foregroundColor(AppSection.profile.ink)
        }
    }

    // MARK: - Reorder View (وضع ترتيب موحّد — الأبناء + البنات)
    /// قائمة ترتيب واحدة تجمع الأبناء (شجرة الرجال) والبنات (شجرة النساء، للإدارة)
    /// بنفس عناصر التحكم. كل فئة تحفظ ترتيبها في جدولها عبر دوال الـ repo القائمة.
    private var childrenReorderView: some View {
        let sons = memberVM.currentMemberChildren
        // البنات تظهر في وضع الترتيب فقط لمن يملك صلاحية حفظ ترتيبها (RLS إدارية).
        let daughters = canReorderDaughters ? womenChildrenList : []
        return VStack(spacing: 0) {
            ForEach(Array(sons.enumerated()), id: \.element.id) { index, son in
                if index > 0 { DSDivider() }
                sonReorderRow(son, index: index, total: sons.count)
            }
            if !sons.isEmpty && !daughters.isEmpty { DSDivider() }
            ForEach(Array(daughters.enumerated()), id: \.element.id) { index, daughter in
                if index > 0 { DSDivider() }
                daughterReorderRow(daughter, index: index, total: daughters.count)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        // «تقليل الحركة»: تلاشٍ فقط بدل الانزلاق من الأعلى
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

    /// صف ترتيب ابن (شجرة الرجال — يحفظ في profiles.sort_order).
    private func sonReorderRow(_ son: FamilyMember, index: Int, total: Int) -> some View {
        let info = childIconInfo(for: son)
        return HStack(spacing: DS.Spacing.md) {
            reorderIndexBadge(index + 1, color: info.color)
            childAvatarView(for: son, iconFont: DS.Glyph.md, size: DS.Icon.avatar)
            Text(son.firstName.isEmpty ? L10n.t("الاسم", "Name") : son.firstName)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer()
            reorderArrows(
                canUp: index > 0,
                canDown: index < total - 1,
                up: {
                    var r = memberVM.currentMemberChildren
                    r.swapAt(index, index - 1)
                    Task { await memberVM.reorderChildren(r) }
                },
                down: {
                    var r = memberVM.currentMemberChildren
                    r.swapAt(index, index + 1)
                    Task { await memberVM.reorderChildren(r) }
                }
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    /// صف ترتيب ابنة (شجرة النساء — يحفظ في women_members.sort_order).
    private func daughterReorderRow(_ daughter: WomanMember, index: Int, total: Int) -> some View {
        let color = daughter.isDeceased ? DS.Color.error : DS.Color.neonPink
        return HStack(spacing: DS.Spacing.md) {
            reorderIndexBadge(index + 1, color: color)
            womanReorderAvatar(daughter)
            Text(daughter.firstName.isEmpty ? L10n.t("الاسم", "Name") : daughter.firstName)
                .dsFont(.rowTitle)
                .foregroundColor(DS.Color.textPrimary)
                .lineLimit(1)
            Spacer()
            reorderArrows(
                canUp: index > 0,
                canDown: index < total - 1,
                up: { moveWomanChild(daughter, up: true) },
                down: { moveWomanChild(daughter, up: false) }
            )
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.xs)
    }

    /// شارة رقم الترتيب.
    private func reorderIndexBadge(_ number: Int, color: Color) -> some View {
        Text("\(number)")
            .dsFont(.chip)
            .foregroundColor(DS.Color.textOnPrimary)
            .frame(width: DS.Icon.orderBadge, height: DS.Icon.orderBadge)
            .background(color)
            .clipShape(Circle())
    }

    /// صورة مصغّرة لابنة شجرة النساء (لصف الترتيب).
    private func womanReorderAvatar(_ woman: WomanMember) -> some View {
        Group {
            if let urlStr = woman.displayImageUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                placeholder: { womanAvatarFallback }
            } else {
                womanAvatarFallback
            }
        }
        .frame(width: DS.Icon.avatar, height: DS.Icon.avatar)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(AppSection.profile.ink.opacity(DS.Opacity.tintFill), lineWidth: DS.Border.width))
    }

    /// أسهم أعلى/أسفل موحّدة (≥44pt) مع تسميات وصول — تُستخدم للأبناء والبنات.
    private func reorderArrows(canUp: Bool, canDown: Bool,
                               up: @escaping () -> Void, down: @escaping () -> Void) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Button(action: up) {
                Image(systemName: "chevron.up")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(canUp ? AppSection.profile.ink : DS.Color.textTertiary.opacity(DS.Opacity.divider))
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .disabled(!canUp)
            .accessibilityLabel(L10n.t("نقل لأعلى", "Move up"))

            Button(action: down) {
                Image(systemName: "chevron.down")
                    .dsGlyph(DS.Glyph.md)
                    .foregroundColor(canDown ? AppSection.profile.ink : DS.Color.textTertiary.opacity(DS.Opacity.divider))
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .disabled(!canDown)
            .accessibilityLabel(L10n.t("نقل لأسفل", "Move down"))
        }
    }

    // MARK: - Helpers

    /// Derives the SF Symbol name and accent color for a child member.
    private func childIconInfo(for member: FamilyMember) -> (name: String, color: Color) {
        let isDeceased = member.isDeceased ?? false
        let isFemale = member.gender?.lowercased() == "female"
        let iconName: String = {
            if isDeceased { return "person.fill.xmark" }
            return isFemale ? "figure.stand.dress" : "person.fill"
        }()
        let iconColor = isDeceased ? DS.Color.error : (isFemale ? DS.Color.neonPink : DS.Color.male)
        return (iconName, iconColor)
    }

    /// Avatar circle for a child — shows the photo if available, otherwise an icon.
    private func childAvatarView(for member: FamilyMember, iconFont: CGFloat, size: CGFloat) -> some View {
        let info = childIconInfo(for: member)
        return ZStack {
            if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                CachedAsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: info.name)
                        .dsGlyph(iconFont)
                        .foregroundColor(info.color)
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: info.name)
                    .dsGlyph(iconFont)
                    .foregroundColor(info.color)
                    .frame(width: size, height: size)
                    .background(info.color.opacity(DS.Opacity.tintFill))
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - General Section (Privacy, Settings)
    /// تسجيل الخروج — زرّ عريض رمادي هادئ (إجراء عادي يرجع منه بالدخول مجدداً) أسفل «حسابي»؛
    /// «حذف الحساب» نصّ أحمر صغير آخر «الإعدادات» — يختلفان شكلاً وحجماً ومكاناً (طلب المالك ٢٠٢٦-١٠-١٠)
    private var signOutButton: some View {
        DSButton(L10n.t("تسجيل الخروج", "Sign Out"), icon: "rectangle.portrait.and.arrow.right",
                 role: .cancel, size: .large) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showSignOutConfirm = true
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.md)
    }
}

/// خلية داخل بطاقات «حسابي» (معلوماتي، طلباتي، عائلتي): صندوق الصفوف الموحّد (`dsRowBox`) —
/// وخانة الإضافة بإطار متقطّع بلونها (نفس خانات «+» المشتركة `DSAddChipLabel`)
private extension View {
    func profileCell(dashed tint: Color? = nil) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .dsRowBox()
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(tint.opacity(DSAddChipLabel.strokeOpacity), style: DSAddChipLabel.dash)
                }
            }
    }
}

// MARK: - Woman-tree family member edit sheet

/// تعديل فرد من «عائلتي» (شجرة النساء): الاسم/تاريخ الميلاد/متوفى + حذف.
struct WomanMemberEditSheet: View {
    @ObservedObject var memberVM: MemberViewModel
    let entry: WomenFamilyEntry
    /// تغيير جنس الابن/الابنة (نقل بين الشجرتين) لمن يعدّل الشجرة فقط — مثل أندرويد
    var canEditGender: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var isDeceased: Bool
    @State private var selectedGender: String
    @State private var deathDate: Date
    @State private var hasDeathDate: Bool
    @State private var selectedUIImage: UIImage? = nil
    @State private var isHidden: Bool
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var errorBanner: String? = nil
    /// نُقل بين الشجرتين بتغيير الجنس — رسالة «تم الحفظ» ثم إغلاق (مثل أندرويد)
    @State private var showMovedAlert = false

    /// تاريخا الميلاد والوفاة كما فُتح المربّع («yyyy-MM-dd» أو nil) — لمقارنة التغييرات
    private let startBirthKey: String?
    private let startDeathKey: String?

    init(memberVM: MemberViewModel, entry: WomenFamilyEntry, canEditGender: Bool = false) {
        self.memberVM = memberVM
        self.entry = entry
        self.canEditGender = canEditGender
        _name = State(initialValue: entry.member.firstName)
        _isDeceased = State(initialValue: entry.member.isDeceased)
        _isHidden = State(initialValue: entry.member.isHiddenFromTree)
        _selectedGender = State(initialValue: entry.member.gender)
        // DateHelper: ميلادي بأرقام لاتينية — formatter الجهاز يقرأ التاريخ خطأ بالتقويم الهجري
        if let d = DateHelper.parse(entry.member.birthDate) {
            _hasBirthDate = State(initialValue: true)
            _birthDate = State(initialValue: d)
            startBirthKey = Self.dayKey(d)
        } else {
            _hasBirthDate = State(initialValue: false)
            _birthDate = State(initialValue: Date())
            startBirthKey = nil
        }
        if let d = DateHelper.parse(entry.member.deathDate) {
            _hasDeathDate = State(initialValue: true)
            _deathDate = State(initialValue: d)
            startDeathKey = Self.dayKey(d)
        } else {
            _hasDeathDate = State(initialValue: false)
            _deathDate = State(initialValue: Date())
            startDeathKey = nil
        }
    }

    private static func dayKey(_ date: Date) -> String { DateHelper.format(date) }

    /// أي حقل يختلف عمّا فُتح عليه المربّع (أو صورة جديدة) — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        let m = entry.member
        if selectedUIImage != nil { return true }
        if name != m.firstName || isDeceased != m.isDeceased
            || isHidden != m.isHiddenFromTree || selectedGender != m.gender { return true }
        let birthKey = hasBirthDate ? Self.dayKey(birthDate) : nil
        let deathKey = hasDeathDate ? Self.dayKey(deathDate) : nil
        return birthKey != startBirthKey || deathKey != startDeathKey
    }

    private var roleTitle: String { L10n.t(entry.role.label, entry.role.labelEn) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving }

    /// الاسم الثلاثي (الأول والثاني والأخير) — عنوان فرعي في رأس المربّع، لأن التعديل على بيانات هذا الشخص
    private var memberName: String {
        // شجرة النساء بلا سلسلة مسجّلة ← نص حرّ (PersonName القاعدة ٣)
        (entry.member.fullName.isEmpty ? entry.member.firstName : entry.member.fullName).nameThreeParts
    }

    var body: some View {
        // مربّع بمنتصف الشاشة بنفس تصميم مربّعات الإضافة (طلب المالك): رأس ملوّن،
        // أقسام تدخل تباعاً، و«حفظ» كحلي يمين و«إلغاء» يسار أسفل المربّع
        DSComposer(
            title: L10n.t("تعديل \(roleTitle)", "Edit \(roleTitle)"),
            subtitle: memberName,
            icon: "person.crop.circle.badge.checkmark",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: canSave,
            isBusy: isSaving,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { save() },
            onCancel: { dismiss() }
        ) {
            // الصورة للذكر فقط — الأنثى بلا خيار صورة
            if selectedGender != "female" {
                // الصورة — قسم مثل أقسام مربّعات الإضافة
                DSComposerSection(title: L10n.t("الصورة الشخصية", "Profile Photo"), icon: "camera.fill",
                                  tint: DS.Color.primary, trailing: L10n.t("اختياري", "Optional"), index: 0) {
                    DSProfilePhotoPicker(
                        selectedImage: $selectedUIImage,
                        existingURL: entry.member.displayImageUrl,
                        enableCrop: true,
                        cropShape: .circle,
                        trailing: nil,
                        compactEmptyState: true
                    )
                    .frame(maxWidth: .infinity)
                }
            }

            personalInfoSection
            datesSection

            if let errorBanner {
                DSNoteCard(errorBanner, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }

            deleteButton
                .dsStaggerIn(3)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(L10n.t("حذف من العائلة", "Remove from family"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                Task {
                    // كلها RPCs مقيّدة على النفس — تعمل لأي دور (الأب/الزوج نفسه).
                    // الأم: فكّ الارتباط · الزوجة: حذف/فكّ · الابنة: حذف السجل.
                    let ok: Bool
                    switch entry.role {
                    case .mother: ok = await memberVM.setSelfMother(motherId: nil)
                    case .wife:   ok = await memberVM.removeSelfWife(wifeId: entry.member.id)
                    default:      ok = await memberVM.removeSelfWomanChild(id: entry.member.id)
                    }
                    // نجاح → إغلاق؛ فشل (مثلاً رفض RLS) → رسالة واضحة بدل لا-عمل صامت.
                    await MainActor.run {
                        if ok {
                            dismiss()
                        } else {
                            errorBanner = memberVM.errorMessage
                                ?? L10n.t("تعذّر الحذف — قد يتطلب موافقة الإدارة.",
                                          "Couldn't remove — this may require an admin.")
                        }
                    }
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(entry.role == .mother
                 ? L10n.t("إزالة الأم «\(name)» من عائلتك؟ (لن تُحذف من الشجرة)", "Unlink mother “\(name)”?")
                 : L10n.t("حذف «\(name)» من عائلتك؟", "Remove “\(name)” from your family?"))
        }
        .dsAlert(L10n.t("تم الحفظ", "Saved"), isPresented: $showMovedAlert) {
            Button(L10n.t("موافق", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تم تحديث بيانات الابن بنجاح.", "Child info updated successfully."))
        }
    }

    /// الاسم (+ الجنس للأبناء، + الإخفاء للزوجة)
    private var personalInfoSection: some View {
        DSComposerSection(title: L10n.t("المعلومات الشخصية", "Personal Info"),
                          icon: "person.text.rectangle",
                          tint: DS.Color.primary,
                          index: 1) {
            DSComposerField(icon: "person.fill",
                            label: L10n.t("الاسم", "Name"),
                            placeholder: L10n.t("الاسم", "Name"),
                            text: $name)
            // الجنس — للأبناء فقط (الأم/الزوجة أنثى دائمًا). تغييره ينقل بين الشجرتين
            // (`move_child_gender`) فهو لمن يعدّل الشجرة؛ لغيرهم للقراءة (مثل أندرويد)
            if entry.role == .child {
                if canEditGender {
                    DSGenderPicker(selection: $selectedGender)
                } else {
                    DSGenderReadOnlyRow(gender: entry.member.gender)
                }
            }
            // الإخفاء — للزوجة فقط، وهي إعداد ذاتي عبر RPC مقيّد.
            if entry.role == .wife {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "eye.slash.fill", tint: DS.Color.textSecondary)
                        .accessibilityHidden(true)
                    Text(L10n.t("إخفاؤها من الشجرة", "Hide from tree"))
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .accessibilityHidden(true)   // يُقرأ اسماً للمفتاح نفسه
                    Spacer(minLength: 0)
                    Toggle("", isOn: $isHidden)
                        .labelsHidden()
                        .tint(AppSection.profile.ink)
                        .accessibilityLabel(L10n.t("إخفاؤها من الشجرة", "Hide from tree"))
                }
                .dsRowBox()
            }
        }
    }

    /// الميلاد ← متوفى ← الوفاة — نفس مربّع التواريخ في «إضافة ابن»
    private var datesSection: some View {
        DSComposerSection(title: L10n.t("التواريخ والحالة", "Dates & Status"),
                          icon: "calendar",
                          tint: DS.Color.warning,
                          index: 2) {
            DSLifeDatesBox(hasBirthDate: $hasBirthDate, birthDate: $birthDate,
                           isDeceased: $isDeceased,
                           hasDeathDate: $hasDeathDate, deathDate: $deathDate,
                           deceasedTitle: L10n.t("متوفى", "Deceased"))
        }
    }

    /// «حذف من العائلة» — الزرّ الواحد بدور الحذف (أحمر)
    private var deleteButton: some View {
        DSButton(L10n.t("حذف من العائلة", "Remove from family"), icon: "trash", role: .destructive) {
            showDeleteConfirm = true
        }
    }

    private func save() {
        Task {
            isSaving = true
            // تغيير جنس الابن/الابنة = نقل بين الشجرتين عبر السيرفر ثم حفظ بقية الحقول على
            // السجل بعد النقل (مثل أندرويد) — لمن يعدّل الشجرة فقط
            let wasMale = entry.member.gender.lowercased() == "male"
            let picked = selectedGender.lowercased()
            if entry.role == .child, canEditGender,
               (picked == "male" && !wasMale) || (picked == "female" && wasMale) {
                await saveMovingGender(toFemale: picked == "female")
                return
            }
            let ok: Bool
            if entry.role == .child {
                // ابنة العضو نفسه — RPC مقيّد على النفس (يعمل لأي دور). تغيير الجنس
                // (نقل بين الشجرتين) يبقى للإدارة؛ هنا الاسم/الميلاد/الوفاة فقط.
                ok = await memberVM.updateSelfWomanChild(
                    id: entry.member.id,
                    firstName: name,
                    birthDate: hasBirthDate ? birthDate : nil,
                    isDeceased: isDeceased,
                    deathDate: hasDeathDate ? deathDate : nil
                )
            } else {
                ok = await memberVM.updateWomanMember(
                    id: entry.member.id,
                    firstName: name,
                    birthDate: hasBirthDate ? birthDate : nil,
                    isDeceased: isDeceased,
                    deathDate: hasDeathDate ? deathDate : nil,
                    gender: selectedGender
                )
            }
            if ok, let img = selectedUIImage {
                await memberVM.updateWomanAvatar(id: entry.member.id, image: img)
            }
            // الإخفاء يمرّ بـRPC ذاتي منفصل (updateWomanMember لا يملك صلاحيته للعضو).
            if ok, entry.role == .wife, isHidden != entry.member.isHiddenFromTree {
                _ = await memberVM.setSelfWifeHidden(wifeId: entry.member.id, hidden: isHidden)
            }
            isSaving = false
            if ok { dismiss() } else { errorBanner = memberVM.errorMessage }
        }
    }

    /// النقل بين الشجرتين ثم حفظ الاسم/التواريخ على السجل الجديد: ذكر → `profiles`
    /// (+ الصورة)، أنثى → `women_members`. أي فشل يظهر في شريط الخطأ (رسالة حماية الروابط كما هي).
    private func saveMovingGender(toFemale: Bool) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // نستبدل الاسم الأول القديم كاملاً (ولو مركّباً) ونحافظ على باقي السلسلة (PersonName القاعدة ١)
        let finalFullName = PersonName.replacingFirstName(in: entry.member.fullName,
                                                          old: entry.member.firstName, new: cleanName)

        guard let newId = await memberVM.moveChildGender(childId: entry.member.id,
                                                         toGender: toFemale ? "female" : "male") else {
            isSaving = false
            errorBanner = memberVM.errorMessage
                ?? L10n.t("فشل حفظ التعديلات. حاول مرة أخرى.", "Save failed. Try again.")
            return
        }
        let ok: Bool
        if toFemale {
            ok = await memberVM.updateWomanMember(
                id: newId, firstName: cleanName,
                birthDate: hasBirthDate ? birthDate : nil,
                isDeceased: isDeceased,
                deathDate: hasDeathDate ? deathDate : nil,
                gender: "female", fullName: finalFullName)
            // يخرج من «الأبناء» في الشجرة العامة
            if let fatherId = entry.member.parentId { await memberVM.fetchChildren(for: fatherId) }
        } else {
            ok = await memberVM.updateChildRow(
                id: newId, fatherId: entry.member.parentId, fullName: finalFullName,
                firstName: cleanName, phoneNumber: nil,
                birthDate: hasBirthDate ? DateHelper.format(birthDate) : nil,
                isDeceased: isDeceased,
                deathDate: isDeceased && hasDeathDate ? DateHelper.format(deathDate) : nil,
                gender: nil)
            if let img = selectedUIImage { await memberVM.uploadAvatar(image: img, for: newId) }
        }
        isSaving = false
        if ok {
            showMovedAlert = true
        } else {
            errorBanner = L10n.t("فشل حفظ التعديلات. حاول مرة أخرى.", "Save failed. Try again.")
        }
    }
}

/// معاينة الصورة الشخصية مكبّرة (طلب المالك) — «تغيير» يفتح معرض الصور مباشرة،
/// ثم قصّ دائري، ثم الرفع (بحدّ الـ٣ تغييرات).
private struct AvatarPreview: View {
    let member: FamilyMember
    let onClose: () -> Void
    let onChangePhoto: (UIImage) async -> String

    @State private var appeared = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var cropItem: CropItem?
    @State private var newImage: UIImage?
    @State private var isUploading = false
    @State private var resultMessage: String?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width - DS.Spacing.xxl * 2, DSBox.mediaMaxSide)
            ZStack {
                DS.Color.overlayDark.opacity(appeared ? DS.Opacity.mediaDim : 0)
                    .ignoresSafeArea()
                    .onTapGesture { if !isUploading { onClose() } }

                VStack(spacing: DS.Spacing.lg) {
                    ZStack {
                        if let newImage {
                            Image(uiImage: newImage).resizable().scaledToFill()
                        } else if let urlStr = member.avatarUrl, let url = URL(string: urlStr) {
                            CachedAsyncImage(url: url) { img in img.resizable().scaledToFill() }
                            placeholder: { ZStack { DS.Color.surface; DSPageLoader(section: .profile) } }
                        } else {
                            DS.Color.surface
                            Text(String(member.firstName.first ?? "?"))
                                .dsFont(.avatarInitialLarge)
                                .foregroundColor(AppSection.profile.ink)
                        }
                        if isUploading {
                            // الرفع: غطاء خافت + التحميل الواحد (المجسّم يتنفّس)
                            DS.Color.hierarchicalSecondary
                            DSPageLoader(section: .profile)
                        }
                    }
                    .frame(width: side, height: side)
                    // سطح المربّع الموحّد (زوايا + إطار + ظلّ)
                    .dsBoxChrome(strong: true)

                    Text(member.displayFullName)
                        .dsFont(.title)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DS.Spacing.xl)

                    if let resultMessage {
                        Text(resultMessage)
                            .dsFont(.callout)
                            .foregroundColor(DS.Color.overlayTextFull)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DS.Spacing.xl)
                    }

                    // «إغلاق» يسار والإجراء في الجهة الأخرى (قاعدة التطبيق) — الزرّ الواحد بمقاس ٤٨
                    HStack(spacing: DSBox.buttonSpacing) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label(L10n.t("تغيير", "Change"), systemImage: "photo.on.rectangle")
                                .modifier(DSButtonFace(size: .large, enabled: !isUploading))
                        }
                        .buttonStyle(DSPressStyle())
                        .disabled(isUploading)

                        // فوق الصورة الداكنة: زجاج أبيض خفيف بدل الرمادي (نصّ أبيض يُقرأ)
                        Button(L10n.t("إغلاق", "Close"), action: onClose)
                            .buttonStyle(.ds(size: .large, tint: DS.Color.overlayIcon))
                            .disabled(isUploading)
                    }
                    .frame(width: side)
                }
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { withAnimation(DS.Anim.snappy) { appeared = true } }
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { cropItem = CropItem(image: img) }
                }
                await MainActor.run { pickerItem = nil }
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

    private func upload(_ image: UIImage) {
        newImage = image
        isUploading = true
        resultMessage = nil
        Task {
            let message = await onChangePhoto(image)
            await MainActor.run {
                isUploading = false
                resultMessage = message
            }
        }
    }

    private struct CropItem: Identifiable {
        let id = UUID()
        let image: UIImage
    }
}


// MARK: - مربّعات الأم/الزوجة عند الخانة نفسها (طلب المالك ٢٠٢٦-٠٩-٢٤)

extension View {
    /// مربّع صغير يخرج من العنصر نفسه (لا ورقة سفلية ولا وسط الشاشة) — فوقه أو
    /// تحته حسب المساحة المتاحة
    @ViewBuilder
    func anchoredPopover<Content: View>(isPresented: Binding<Bool>,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        if #available(iOS 18.0, *) {
            popover(isPresented: isPresented, attachmentAnchor: .rect(.bounds), arrowEdge: nil) {
                content().presentationCompactAdaptation(.popover)
            }
        } else {
            popover(isPresented: isPresented, arrowEdge: .bottom) {
                if #available(iOS 16.4, *) {
                    content().presentationCompactAdaptation(.popover)
                } else {
                    content()
                }
            }
        }
    }
}

/// أزرار المربّع — صفّ الأزرار الموحّد: الإجراء بتعبئة القسم و«إلغاء» رمادي على اليسار (قاعدة التطبيق)
private struct AnchoredCardButtons: View {
    let actionTitle: String
    var actionEnabled = true
    var busy = false
    let onAction: () -> Void
    let onCancel: () -> Void

    var body: some View {
        DSBoxButtons {
            Button(action: onAction) {
                if busy { ProgressView().tint(DS.Color.textOnPrimary) } else { Text(actionTitle) }
            }
            .disabled(!actionEnabled || busy)
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel, action: onCancel)
        }
    }
}

/// صف اختيار داخل المربّع
private struct AnchoredChoiceRow: View {
    let title: String
    let icon: String
    /// سطر صغير يشرح الخيار تحت عنوانه (اختياري)
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // صفّ بإطار حقول المربّعات: قرص مجسّم + عنوان (+ سطر الشرح)
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: icon, tint: AppSection.profile.ink)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title)
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    if let hint {
                        Text(hint)
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(minHeight: DSBox.fieldMinHeight)
            .dsRowBox()
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }
}

/// حقل الاسم داخل المربّع — نفس شكل حقول المربّعات
private struct AnchoredNameField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .dsAlertField()
            .focused($focused)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { focused = true } }
    }
}

/// الأم: زوجات الأب للاختيار، أو «من أين الأم؟» — من العائلة (مربّع الأب ← بناته) أو من خارجها بالاسم
private struct MotherPickCard: View {
    let wives: [WomanMember]
    let onPick: (UUID) -> Void
    let onAdd: (String) -> Void
    /// «من العائلة» — مربّع «أبوها ← بناته» نفسه مع الزوجة
    let onTree: () -> Void
    let onCancel: () -> Void
    /// زوجة موجودة: «تعديل» داخل مربّع الإضافة نفسه (طلب المالك ٢٠٢٦-١٠-٢٨) — بلا اسمها (أسماء النساء مستورة)
    var onEdit: (() -> Void)? = nil
    @State private var adding = false
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(adding ? L10n.t("إضافة أم", "Add Mother") : L10n.t("الأم", "Mother"))
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity)
            if adding {
                AnchoredNameField(placeholder: L10n.t("اسم الأم", "Mother's name"), text: $name)
                AnchoredCardButtons(
                    actionTitle: L10n.t("إضافة", "Add"),
                    actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                    onAction: { onAdd(name.trimmingCharacters(in: .whitespaces)) },
                    onCancel: { withAnimation(.easeInOut(duration: 0.2)) { adding = false } })
            } else {
                Text(wives.isEmpty
                     ? L10n.t("من أين الأم؟", "Where is she from?")
                     : L10n.t("اختر الأم من زوجات الأب، أو من أين هي؟", "Pick from the father's wives, or where is she from?"))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                ForEach(wives) { w in
                    AnchoredChoiceRow(title: w.firstName.isEmpty ? L10n.t("زوجة الأب", "Father's wife") : w.firstName,
                                      icon: "person.fill") { onPick(w.id) }
                }
                AnchoredChoiceRow(title: L10n.t("من العائلة", "From the family"), icon: "tree.fill",
                                  hint: L10n.t("أبوها في الشجرة — تختارها من بناته أو تضيفها تحته",
                                               "Her father is in the tree — pick her or add her under him"),
                                  action: onTree)
                AnchoredChoiceRow(title: L10n.t("من خارج العائلة", "From outside the family"),
                                  icon: "person.crop.circle.badge.plus",
                                  hint: L10n.t("تكتب اسمها", "Type her name")) {
                    withAnimation(.easeInOut(duration: 0.2)) { adding = true }
                }
                DSButton(L10n.t("إلغاء", "Cancel"), role: .cancel, action: onCancel)
            }
        }
        .padding(DS.Spacing.md)
        .frame(width: DSBox.popoverWidth)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

/// «إضافة زوجة» الواحدة (طلب المالك ٢٠٢٦-١٠-٢٥): من أين هي؟ — من العائلة (مربّع «أبوها ← بناته» المشترك
/// مع شجرة النساء)، أو من خارجها بالاسم (مع خيار الإخفاء) في نفس المربّع
private struct WifeSourceCard: View {
    /// «من العائلة» — كان خياران: «اختيار من العائلة» بالاسم الرباعي و«من بنات الشجرة»
    let onFamily: () -> Void
    /// يرجع رسالة الخطأ، أو nil عند النجاح
    let onAdd: (String, Bool) async -> String?
    let onCancel: () -> Void
    /// زوجة موجودة: «تعديل» داخل مربّع الإضافة نفسه (طلب المالك ٢٠٢٦-١٠-٢٨) — بلا اسمها (أسماء النساء مستورة)
    var onEdit: (() -> Void)? = nil
    @State private var adding = false
    @State private var name = ""
    @State private var hidden = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(L10n.t("إضافة زوجة", "Add Wife"))
                .dsFont(.headline)
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity)
            if adding {
                AnchoredNameField(placeholder: L10n.t("اسم الزوجة", "Wife's name"), text: $name)
                Toggle(isOn: $hidden) {
                    Text(L10n.t("إخفاؤها من الشجرة", "Hide from the tree"))
                        .dsFont(.callout)
                        .foregroundColor(DS.Color.textPrimary)
                }
                .tint(AppSection.profile.ink)
                if hidden {
                    Text(L10n.t("المخفيّة لا تظهر لأي أحد في الشجرة — تبقى مسجّلة عندك فقط.",
                                "A hidden wife appears to no one in the tree — she stays recorded for you only."))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textSecondary)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.error)
                }
                AnchoredCardButtons(
                    actionTitle: L10n.t("إضافة", "Add"),
                    actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                    busy: busy,
                    onAction: {
                        busy = true; error = nil
                        Task {
                            let e = await onAdd(name.trimmingCharacters(in: .whitespaces), hidden)
                            busy = false
                            error = e
                        }
                    },
                    onCancel: { withAnimation(.easeInOut(duration: 0.2)) { adding = false; error = nil } })
            } else {
                if let onEdit {
                    AnchoredChoiceRow(title: L10n.t("تعديل الزوجة", "Edit Wife"),
                                      icon: "pencil",
                                      hint: L10n.t("الاسم والتواريخ والصورة", "Name, dates and photo"),
                                      action: onEdit)
                }
                AnchoredChoiceRow(title: L10n.t("من العائلة", "From the family"), icon: "tree.fill",
                                  hint: L10n.t("أبوها في الشجرة — تختارها من بناته أو تضيفها تحته",
                                               "Her father is in the tree — pick her or add her under him"),
                                  action: onFamily)
                AnchoredChoiceRow(title: L10n.t("من خارج العائلة", "From outside the family"),
                                  icon: "person.crop.circle.badge.plus",
                                  hint: L10n.t("تكتب اسمها", "Type her name")) {
                    withAnimation(.easeInOut(duration: 0.2)) { adding = true }
                }
                DSButton(L10n.t("إلغاء", "Cancel"), role: .cancel, action: onCancel)
            }
        }
        .padding(DS.Spacing.md)
        .frame(width: DSBox.popoverWidth)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }
}

// MARK: - اسم «حسابي» مع القلم
extension ProfileView {
    func profileNameLine(_ name: String) -> Text {
        Text(name)
            .font(DS.Font.role(.pageTitle))
            .foregroundColor(DS.Color.textPrimary)
        + Text("  ")
        + Text(Image(systemName: "pencil.circle.fill"))
            .font(DS.Glyph.font(DS.Glyph.xl))
            .foregroundColor(AppSection.profile.ink)
    }
}

// MARK: - «الأب غير موجود؟» من مربّع الزوجة/الأم — طلب للإدارة (طلب المالك ٢٠٢٦-١٠-٢٥)
extension ProfileView {
    func requestMissingFather(_ typed: String, me: FamilyMember, relation: DSWifeFlowBox.Relation) {
        guard NetworkMonitor.shared.requireOnline() else { return }
        let payload = WifeCandidateRules.missingFatherPayload(typed: typed, memberId: me.id,
                                                              memberName: me.displayFullName, relation: relation)
        Task {
            let sent = await adminRequestVM.submitTreeEditRequest(payload: payload)
            try? await Task.sleep(nanoseconds: 350_000_000)
            treeDaughterDoneMessage = sent
                ? L10n.t("وصل طلبك للإدارة — يضيفون الأب أو يصلحون بياناته ثم يكملون الربط.",
                         "Sent to the admins — they'll add or fix the father, then complete the link.")
                : L10n.t("لم يُرسل الطلب. تحقّق من الاتصال وحاول مرة أخرى.",
                         "The request wasn't sent. Check your connection and try again.")
        }
    }
}

// MARK: - «إضافة زوجة» من العائلة في «حسابي» (طلب المالك ٢٠٢٦-١٠-٢٥ «حتى في الملف الشخصي»)

/// نفس مربّع شجرة النساء (`DSWifeFlowBox`) بآلية «عائلتي»: أبوها من الشجرة ← بناته المتاحات (قواعد
/// `WifeCandidateRules`: لا متزوجة ولا دون ١٨ ولا مولودة حديثاً) ← ربطها، أو «أضفها تحت أبيها» — كله بدالة
/// السيرفر الذاتية `add_or_link_self_relative` (كان «اختيار من العائلة» بالاسم الرباعي و«من بنات الشجرة» خيارين)
private struct ProfileWifeFamilyBox: View {
    @ObservedObject var memberVM: MemberViewModel
    let me: FamilyMember
    /// زوجتك أو أمك — المربّع نفسه ودالة السيرفر نفسها بنوعها
    var relation: DSWifeFlowBox.Relation = .wife
    /// «الأب غير موجود؟» — المضيف يرسل الطلب للإدارة
    var onFatherMissing: ((String) -> Void)? = nil
    let onDone: (String) -> Void
    let onCancel: () -> Void

    @State private var people: [FamilyMember] = WomenStore.cache
    @State private var isLoading = WomenStore.cache.isEmpty
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        DSWifeFlowBox(mode: .selfFamily, relation: relation, husbandId: me.id, personFatherId: me.fatherId,
                      husbandName: me.firstName.isEmpty ? me.fullName : me.firstName,
                      subtitle: relation == .mother ? L10n.t("أمك من العائلة", "Your mother from the family")
                                                    : L10n.t("زوجتك من العائلة", "Your wife from the family"),
                      people: people, isLoading: isLoading, startsAtFather: true,
                      isBusy: busy, error: error,
                      onLink: { daughter, father in write(father: father, womanId: daughter.id, name: nil) },
                      onAddUnderFather: { name, father in write(father: father, womanId: nil, name: name) },
                      onFatherMissing: onFatherMissing,
                      onCancel: onCancel)
            // شجرة النساء طازجة (الآباء والبنات) — جلب فارغ أو فاشل يُبقي آخر نسخة
            .task {
                let cached = WomenStore.cache
                let fresh = (try? await WomenStore.fetch()) ?? []
                people = fresh.isEmpty ? cached : fresh
                isLoading = false
            }
    }

    private func write(father: FamilyMember, womanId: UUID?, name: String?) {
        guard !busy, NetworkMonitor.shared.requireOnline() else { return }
        busy = true; error = nil
        Task {
            do {
                let kind = relation == .mother ? "mother" : "wife"
                try await WomenStore.addOrLinkSelfRelative(kind: kind, fatherId: father.id, womanId: womanId, name: name)
                Log.info("[Women] add_or_link_self_relative \(kind) \(womanId == nil ? "new" : "link")")
                // نفس التحديث بعد اختيار الأم وإضافتها
                await memberVM.fetchWomenFamily(for: me.id)
                busy = false
                onDone(relation == .mother ? L10n.t("صارت أمك في «عائلتي».", "She's now your mother in «My family».")
                                           : L10n.t("صارت زوجتك في «عائلتي».", "She's now your wife in «My family»."))
            } catch {
                busy = false
                Log.error("[Women] add_or_link_self_relative: \(error.localizedDescription)")
                self.error = Self.message(for: error)
            }
        }
    }

    /// رموز السيرفر (`hint`) ← رسائل قصيرة
    static func message(for error: Error) -> String {
        switch (error as? PostgrestError)?.hint {
        case "not_allowed":
            return L10n.t("حسابك غير مفعّل بعد.", "Your account isn't active yet.")
        case "no_node":
            return L10n.t("السجل غير موجود في الشجرة — تواصل مع الإدارة.", "Not found in the tree — contact the admins.")
        case "not_daughter":
            return L10n.t("المختارة ليست من بنات هذا الأب.", "She isn't a daughter of this father.")
        case "already_married":
            return L10n.t("هذه البنت مرتبطة بزوج آخر.", "She's already linked to a husband.")
        case "name_required":
            return L10n.t("اكتب الاسم.", "Enter the name.")
        case "mother_set_not_allowed":
            return L10n.t("أمك محدّدة مسبقاً — تواصل مع الإدارة لتغييرها.", "Your mother is already set — contact the admins to change it.")
        case "no_own_father":
            return L10n.t("أبوك غير مسجّل في الشجرة بعد.", "Your father isn't in the tree yet.")
        default:
            return WomenStore.failureMessage(error)
        }
    }
}
