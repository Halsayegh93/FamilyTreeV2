import SwiftUI
import Supabase

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @FocusState private var isFieldFocused: Bool

#if DEBUG
    /// معاينة شاشة تسجيل البيانات بلا رقم جديد — نسخة التطوير فقط
    @State private var previewRegistration = false
    /// خطوة المعاينة: تسجيل البيانات ← شاشة الانتظار
    @State private var previewStep = 0
#endif
    @State private var timeRemaining = 0
    @State private var otpTimeRemaining = 0
    @State private var logoScale: CGFloat = 0.94
    @State private var logoOpacity: CGFloat = 0
    /// «الخصوصية والاستخدام» قبل الدخول (Guideline 5.1.1)
    @State private var showLegal = false




    private var phoneBinding: Binding<String> {
        Binding(
            get: { authVM.phoneNumber },
            set: { newValue in
                authVM.phoneNumber = String(
                    KuwaitPhone.normalizeDigits(newValue)
                        .filter(\.isNumber)
                        .prefix(15)
                )
            }
        )
    }

    private var countryCodeBinding: Binding<String> {
        Binding(
            get: { authVM.dialingCode },
            set: { newValue in
                let digits = KuwaitPhone.normalizeDigits(newValue).filter(\.isNumber)
                let prefix = String(digits.prefix(4))
                authVM.dialingCode = prefix.isEmpty ? "+" : "+\(prefix)"
            }
        )
    }

    /// ربط كود الاتصال بـ KuwaitPhone.Country لاستخدام حقل الهاتف الموحّد.
    private var countryBinding: Binding<KuwaitPhone.Country> {
        Binding(
            get: { KuwaitPhone.countryForDialingCode(authVM.dialingCode) },
            set: { authVM.dialingCode = $0.dialingCode }
        )
    }

    @State private var otpText: String = ""
    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الوضع الأفقي — نلف المحتوى بـScrollView
    private var isLandscape: Bool { vSizeClass == .compact }

    var body: some View {
        ZStack {
            // خلفية ديناميكية متحركة
            backgroundView

            Group {
                if isLandscape {
                    // الوضع الأفقي: المحتوى داخل ScrollView حتى لا يُقتص شيء
                    ScrollView(showsIndicators: false) {
                        loginContent
                            .padding(.vertical, DS.Spacing.lg)
                    }
                } else {
                    loginContent
                }
            }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .animation(DS.Anim.bouncy, value: authVM.isOtpSent)
        .onAppear {
            // رجع للتطبيق بعد ما أغلقه النظام وهو في «الرسائل»: خانة الرمز من جديد بعدّاداتها
            if let elapsed = authVM.restorePendingOTPIfAny() {
                timeRemaining = max(0, Self.resendSeconds - Int(elapsed))
                otpTimeRemaining = max(0, Int(AuthViewModel.pendingOTPLifetime - elapsed))
            }
            // «تقليل الحركة»: الشعار يظهر بتلاشٍ فقط بلا تكبير
            guard !reduceMotion else {
                logoScale = 1.0
                withAnimation(DSMotion.fade) { logoOpacity = 1.0 }
                return
            }
            // ظهور هادئ قصير للشعار: تلاشٍ وتكبير خفيف (الهوية)
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
        .task { await Self.refreshResendSeconds() }
        .task(id: timeRemaining) {
            guard timeRemaining > 0 else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { timeRemaining -= 1 }
        }
        .task(id: otpTimeRemaining) {
            guard otpTimeRemaining > 0, authVM.isOtpSent else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if !Task.isCancelled { otpTimeRemaining -= 1 }
        }

    }

    /// محتوى شاشة الدخول — نفسه في الوضعين، يُلف بـScrollView أفقياً فقط
    private var loginContent: some View {
            VStack(spacing: 0) {
                if authVM.isOtpSent {
                    // خطوة الرمز — الهيدر الموحّد بدل الشعار
                    authHeader(
                        icon: "lock.shield.fill",
                        title: L10n.t("رمز التحقق", "Verification Code"),
                        subtitle: L10n.t("أدخل الرمز المرسل لجوالك", "Enter the code sent to your phone"),
                        actionIcon: DSBackButton.symbol,   // سهم الرجوع الموحّد
                        action: {
                            withAnimation(DS.Anim.smooth) {
                                authVM.isOtpSent = false; authVM.cancelPendingOTP()
                                authVM.otpCode = ""; otpText = ""
                                authVM.otpErrorMessage = nil
                                authVM.otpStatusMessage = ""
                                timeRemaining = 0
                            }
                        }
                    )
                }

                Spacer()

                if !authVM.isOtpSent {
                    // شعار متحرك — Elegant
                    logoSection
                        .scaleEffect(logoScale)
                        .opacity(logoOpacity)
                        .padding(.bottom, isLandscape ? DS.Spacing.xl : DS.Spacing.xxxxl)
                }

                // مؤشر التقدم — خطوة ١ / خطوة ٢
                // بعد الشعار تدخل الأقسام بالترتيب: المؤشر ← بطاقة الإدخال ← الشروط (مرة عند الظهور)
                HStack(spacing: DS.Spacing.sm) {
                    stepDot(filled: true)
                    stepDot(filled: authVM.isOtpSent)
                }
                .padding(.bottom, DS.Spacing.sm)
                .dsStaggerIn(0)

                // منطقة الإدخال
                VStack(spacing: DS.Spacing.xl) {
                    if !authVM.isOtpSent {
                        phoneInputSection
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.9))
                            ))
                    } else {
                        otpInputSection
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.9)),
                                removal: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.9))
                            ))
                    }
                }
                .frame(maxWidth: DSBox.formMaxWidth)
                .padding(.horizontal, DS.Spacing.xl)
                // الحاوية تدخل مرة واحدة — تبديل الرقم ↔ الرمز يبقى بانتقاله كما هو
                .dsStaggerIn(1)

                Spacer()

                // الشروط والخصوصية متاحة قبل الدخول — تُقرأ داخل التطبيق
                if !authVM.isOtpSent {
                    legalFooter
                        .padding(.bottom, DS.Spacing.sm)
                        .dsStaggerIn(2)
                }
            }
            // الأقسام تبدأ بعد الشعار (نفس «بعد الرأس» في المربّعات)
            .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
    }

    /// سطر واحد صغير أسفل الشاشة: «بالمتابعة توافق على «الخصوصية والاستخدام»» — الاسم يُضغط فيفتح المربّع
    /// (طلب المالك ٢٠٢٦-١٠-٢٧؛ كان «باستخدامك التطبيق فإنك توافق على شروط الاستخدام وسياسة الخصوصية» بسطرين)
    private var legalFooter: some View {
        Button { showLegal = true } label: {
            (Text(L10n.t("بالمتابعة توافق على ", "By continuing you agree to "))
                .foregroundColor(DS.Color.textTertiary)
             + Text(L10n.t("الخصوصية والاستخدام", "Privacy & Use"))
                .foregroundColor(DS.Color.primary)
                .underline())
                .dsFont(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.md)
                .frame(minHeight: DS.Icon.tapTarget)   // مساحة ضغط ٤٤ (توصية أبل)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح الخصوصية والاستخدام", "Opens Privacy & Use"))
        .frame(maxWidth: .infinity)
        .dsTallBox(isPresented: $showLegal) { PrivacyPolicyView() }
    }

    /// مربّع رقم واحد من رمز التحقق — يبرز المربّع النشط
    private func otpBox(at index: Int) -> some View {
        let chars = Array(otpText)
        let digit = index < chars.count ? String(chars[index]) : ""
        let isActive = isFieldFocused && index == min(chars.count, 5)
        let isFilled = !digit.isEmpty

        return Text(digit)
            .dsFont(.codeDigit)
            .foregroundColor(DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Icon.sizeLg)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(
                        isActive ? DS.Color.primary
                        : isFilled ? DS.Color.primary.opacity(DS.Opacity.tintStroke)
                        : DS.Color.inactiveBorder,
                        lineWidth: isActive ? DS.Border.widthBold : DS.Border.width
                    )
            )
            .overlay(alignment: .center) {
                // مؤشّر نبض في المربّع الفارغ النشط
                if isActive && !isFilled {
                    Capsule()
                        .fill(DS.Color.primary)
                        .frame(width: DS.Border.widthBold, height: DS.Icon.section)
                        .opacity(DS.Opacity.dimmed)
                }
            }
            .animation(DS.Anim.quick, value: isActive)
            .animation(DS.Anim.quick, value: isFilled)
    }

    // MARK: - Background
    private var backgroundView: some View {
        ZStack {
            // خلفية صلبة (الهوية: بلا تدرّج)
            DS.Color.background
                .ignoresSafeArea()
            // بلا هالة ولا حلقة حول الشعار (طلب المالك ٢٠٢٦-١٠-١٧: «في إطار في تسجيل الدخول»)
        }
    }

    // MARK: - Logo — شعار العائلة المسطّح
    /// ارتفاع الشعار؛ المسافة بينه وبين الاسم (DS.Spacing.xl) ربع ارتفاعه — مسافة الهوية الآمنة
    private var logoHeight: CGFloat { isLandscape ? 64 : 80 }

    private var logoSection: some View {
        VStack(spacing: DS.Spacing.xl) {
            // الشعار المسطّح «المحمدعلي»: كحلي على الفاتح، كريمي في الداكن — بلا دائرة ولا ظل (الهوية)
            // الشعار القديم (أيقونة التطبيق الدائرية) — طلب المالك ٢٠٢٦-١٠-١٧: يبقى حتى يتبدّل مع الأيقونة الجديدة
            Image("AppIconImage")
                .resizable()
                .scaledToFill()
                .frame(width: logoHeight * 1.25, height: logoHeight * 1.25)
                .clipShape(Circle())
                .dsSubtleShadow()
                .accessibilityLabel(L10n.t("شعار عائلة المحمدعلي", "Al-Mohammad Ali family logo"))
#if DEBUG
                // ضغطة مطوّلة على الشعار تفتح شاشة تسجيل البيانات للمعاينة
                // بلا رقم جديد. لا تُبنى إطلاقاً في نسخة الإصدار.
                .onLongPressGesture(minimumDuration: 1.5) {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    previewRegistration = true
                }
                .fullScreenCover(isPresented: $previewRegistration) {
                    ZStack(alignment: .top) {
                        if previewStep == 0 {
                            RegistrationView(topInset: 46)
                        } else {
                            WaitingForApprovalView()
                        }

                        // شريط تنقّل المعاينة — إغلاق + تبديل الشاشتين
                        HStack(spacing: DS.Spacing.sm) {
                            Button {
                                previewRegistration = false
                                previewStep = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .dsGlyph(DS.Glyph.xxl, weight: .regular)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(DS.Color.textOnPrimary, DS.Color.shadowHeavy)
                            }

                            Text(L10n.t("شاشة معاينة", "Preview"))
                                .dsFont(.badge)
                                .foregroundColor(DS.Color.textSecondary)

                            // نفس مبدّل الأقسام الموحّد بدل مبدّل النظام (مثل معاينة الرئيسية)
                            DSSegmentedSwitch(options: [
                                DSSegmentOption(id: 0, title: L10n.t("البيانات", "Profile"), icon: "person.text.rectangle"),
                                DSSegmentOption(id: 1, title: L10n.t("الانتظار", "Waiting"), icon: "hourglass")
                            ], selection: $previewStep, size: .regular)
                            .frame(maxWidth: 240)
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .dsGlass(Capsule())
                        .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.fieldStroke),
                                                        lineWidth: DS.Border.width))
                        .dsCardShadow()
                        .padding(.top, DS.Spacing.xxxxl * 3)
                    }
                }
#endif

            VStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("عائلة المحمدعلي", "Al-Mohammad Ali family"))
                    .dsFont(.heroTitle)
                    .foregroundColor(DS.Color.textPrimary)

                Text(L10n.t("شجرة العائلة", "Family Tree"))
                    .dsFont(.body)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
    }

    /// بين رمز ورمز — يُقرأ من الإعدادات (`sms_resend_seconds()` = «حماية رسائل الدخول ← بين رمز ورمز»، المالك
    /// ٢٠٢٦-١٠-٢٤)؛ آخر قيمة محفوظة على الجهاز، وبلا قيمة ٣ دقائق
    static let resendSecondsKey = "smsResendSeconds.v1"
    static var resendSeconds: Int {
        let n = UserDefaults.standard.integer(forKey: resendSecondsKey)
        return n > 0 ? n : 180
    }

    /// تحديث «بين رمز ورمز» من السيرفر (قبل الدخول) — أي خطأ يبقي القيمة السابقة
    static func refreshResendSeconds() async {
        guard let n: Int = try? await SupabaseConfig.client.rpc("sms_resend_seconds").execute().value,
              (30...3600).contains(n) else { return }
        UserDefaults.standard.set(n, forKey: resendSecondsKey)
    }

    /// وقت الانتظار على الزر: «45ث» · «1:59» · «ساعة» (حد الساعة أو اليوم — `OTPWaitText.hourThreshold`)
    static func waitLabel(_ n: Int) -> String {
        if n >= OTPWaitText.hourThreshold { return L10n.t("ساعة", "an hour") }
        if n < 60 { return L10n.t("\(n)ث", "\(n)s") }
        return String(format: "%d:%02d", n / 60, n % 60)
    }

    // MARK: - Phone Input — Compact Card
    @ViewBuilder
    var phoneInputSection: some View {
        let isPhoneValid = authVM.phoneNumber.count >= 6
        let isTimerActive = timeRemaining > 0
        let isLoading = authVM.isLoading
        let isDisabled = !isPhoneValid || isTimerActive || isLoading

        VStack(spacing: DS.Spacing.lg) {
            // حقل الهاتف الموحّد — كود الدولة على الجهة المقابلة
            DSPhoneField(
                country: countryBinding,
                digits: $authVM.phoneNumber,
                placeholder: L10n.t("رقم الهاتف المحمول", "Mobile Number"),
                isFocused: isFieldFocused
            )

            // زر الإرسال — DSPrimaryButton
            DSPrimaryButton(
                timeRemaining > 0
                    ? L10n.t("إعادة الطلب بعد \(Self.waitLabel(timeRemaining))", "Resend in \(Self.waitLabel(timeRemaining))")
                    : L10n.t("متابعة", "Continue"),
                icon: timeRemaining > 0 ? nil : "arrow.forward",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? DS.Color.inactive : DS.Color.primary
            ) {
                guard !isDisabled else { return }
                isFieldFocused = false
                timeRemaining = Self.resendSeconds
                authVM.otpCode = ""; otpText = ""
                Task {
                    await authVM.sendOTP()
                    // رفض السيرفر بمهلة (حد الرقم أو «رمز واحد لكل دقيقتين») ← الزر يُقفل بوقت السيرفر نفسه،
                    // وأي فشل آخر يفتحه (المالك ٢٠٢٦-١٠-٢٣: «ابى الزر يرتبط بالسيرفر»)
                    if !authVM.isOtpSent { timeRemaining = authVM.otpRetryAfter ?? 0 }
                }
            }
            .disabled(isDisabled)

            // رسالة الخطأ/الحالة في خطوة الرقم أيضاً — كان الفشل صامتاً هنا
            statusMessage
                .animation(DS.Anim.snappy, value: authVM.otpErrorMessage)
        }
        // البطاقة الواحدة
        .dsCard(padding: DS.Spacing.lg)
    }

    // MARK: - OTP Input — Compact Card
    @ViewBuilder
    var otpInputSection: some View {
        let isOtpValid = authVM.otpCode.count == 6
        let isLoading = authVM.isLoading
        let isExpired = otpTimeRemaining == 0
        let otpDisabled = !isOtpValid || isLoading || isExpired

        VStack(spacing: DS.Spacing.xl) {
            VStack(spacing: DS.Spacing.sm) {
                // أيقونة القفل — قرص مجسّم
                DSStateIcon("lock.shield.fill", tint: DS.Color.primary, size: DS.Icon.size)

                Text(L10n.t("رمز التحقق", "Verification Code"))
                    .dsFont(.headline)
                    .foregroundColor(DS.Color.textPrimary)

                HStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("أرسلنا رمزاً إلى", "Code sent to"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                    Text("\(authVM.dialingCode) \(authVM.phoneNumber)")
                        .dsFont(.rowTitle)
                        .foregroundStyle(DS.Color.primary)

                    Button(action: {
                        withAnimation(DS.Anim.smooth) {
                            authVM.isOtpSent = false; authVM.cancelPendingOTP()
                            authVM.otpCode = ""; otpText = ""
                            authVM.otpErrorMessage = nil
                            authVM.otpStatusMessage = ""
                            timeRemaining = 0
                        }
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .dsGlyph(DS.Glyph.lg, weight: .regular)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.leading, DS.Spacing.xs)
                }

                // وقت واحد ظاهر = عدّاد «إعادة عبر SMS» (المالك ٢٠٢٦-١٠-٢٤ «في وقتين … نبي وقت واحد»)؛ صلاحية
                // الرمز (٥ دقائق) تُحسب بصمت وتظهر سطراً فقط بعد ما تنتهي
                if otpTimeRemaining == 0 {
                    Text(L10n.t("انتهت صلاحية الرمز", "Code has expired"))
                        .dsFont(.caption)
                        .foregroundStyle(DS.Color.error)
                        .padding(.top, DS.Spacing.xs)
                }
            }

            // حقل OTP — ستة مربّعات فوق حقل مخفي يحافظ على AutoFill
            ZStack {
                TextField("", text: $otpText)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFieldFocused)
                    // مخفي بصرياً لا وظيفياً — يبقى مستقبِلاً للوحة المفاتيح
                    .opacity(0.001)
                    .frame(height: DS.Icon.sizeLg)
                    .accessibilityLabel(L10n.t("رمز التحقق", "Verification Code"))

                HStack(spacing: DS.Spacing.sm) {
                    ForEach(0..<6, id: \.self) { i in
                        otpBox(at: i)
                    }
                }
                // الرمز يُملأ من اليسار لليمين حتى مع واجهة عربية
                .environment(\.layoutDirection, .leftToRight)
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { isFieldFocused = true }
                .onAppear {
                    isFieldFocused = true
                    otpText = ""
                    authVM.otpCode = ""
                    // الرجوع لخانة رمز محفوظ يبدأ من الوقت الباقي له (`restorePendingOTPIfAny`)
                    if otpTimeRemaining == 0 { otpTimeRemaining = 300 }
                }
                .onChange(of: otpText) { newValue in
                    // يقبل الأرقام العربية والفارسية ويحوّلها إنجليزية — نفس حقل الهاتف
                    let digits = KuwaitPhone.normalizeDigits(newValue).filter(\.isNumber)
                    let limited = String(digits.prefix(6))
                    // فقط صحّح إذا فيه حروف غير أرقام
                    if newValue != limited {
                        otpText = limited
                        return
                    }
                    authVM.otpCode = limited
                    if limited.count == 6 {
                        isFieldFocused = false
                        Task { await authVM.verifyOTP() }
                    }
                }

            VStack(spacing: DS.Spacing.md) {
                // زر التأكيد — DSPrimaryButton
                DSPrimaryButton(
                    L10n.t("تأكيد الدخول", "Verify"),
                    icon: "checkmark.shield.fill",
                    isLoading: authVM.isLoading,
                    useGradient: !otpDisabled,
                    color: otpDisabled ? DS.Color.inactive : DS.Color.primary
                ) {
                    Task { await authVM.verifyOTP() }
                }
                .disabled(otpDisabled)
            }

            statusMessage

            // إعادة طلب الرمز — SMS (واتساب يظهر فقط إذا feature flag مفعّل)
            // إعادة الإرسال — الشريحة الواحدة (رمادية أثناء الانتظار)
            HStack(spacing: DS.Spacing.md) {
                DSChipButton(timeRemaining > 0
                             ? L10n.t("بعد \(Self.waitLabel(timeRemaining))", "in \(Self.waitLabel(timeRemaining))")
                             : L10n.t("إعادة عبر SMS", "Resend via SMS"),
                             icon: "message.fill",
                             tint: timeRemaining > 0 ? DS.Color.textTertiary : DS.Color.primary) {
                    authVM.otpCode = ""; otpText = ""
                    authVM.otpErrorMessage = nil
                    authVM.otpStatusMessage = ""
                    otpTimeRemaining = 300
                    timeRemaining = Self.resendSeconds
                    Task {
                        await authVM.sendOTP(channel: .sms)
                        // محجوب بمهلة معروفة (نفس الرقم): عدّاد «إعادة عبر SMS» يبدأ منها، وإلا ٣٠ ث كما كان
                        if authVM.otpErrorMessage != nil { timeRemaining = authVM.otpRetryAfter ?? 30 }
                    }
                }
                .disabled(authVM.isLoading || timeRemaining > 0)

                if AuthViewModel.whatsappOTPEnabled {
                    DSChipButton(L10n.t("إرسال عبر واتساب", "Send via WhatsApp"),
                                 icon: "bubble.left.and.bubble.right.fill",
                                 tint: authVM.isLoading ? DS.Color.textTertiary : DS.Color.sea) {
                        authVM.otpCode = ""; otpText = ""
                        authVM.otpErrorMessage = nil
                        authVM.otpStatusMessage = ""
                        otpTimeRemaining = 300
                        timeRemaining = 60
                        Task {
                            await authVM.sendOTP(channel: .whatsapp)
                            if authVM.otpErrorMessage != nil { timeRemaining = 30 }
                        }
                    }
                    .disabled(authVM.isLoading)
                }
            }
        }
        // البطاقة الواحدة
        .dsCard(padding: DS.Spacing.lg)
    }

    @ViewBuilder
    private var statusMessage: some View {
        // الملاحظة الملوّنة الواحدة بلون معناها (خطأ / نجاح)
        if let error = authVM.otpErrorMessage {
            DSNoteCard(error, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                .transition(.scale.combined(with: .opacity))
        } else if !authVM.otpStatusMessage.isEmpty {
            DSNoteCard(authVM.otpStatusMessage, icon: "checkmark.circle.fill", tint: DS.Color.success)
                .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Step Dot
    private func stepDot(filled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(filled ? DS.Color.primaryFill : DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                .frame(width: DS.Glyph.xs, height: DS.Glyph.xs)
            if filled {
                Circle()
                    .fill(DS.Color.textOnPrimary)
                    .frame(width: DS.Spacing.xs, height: DS.Spacing.xs)
            }
        }
        .animation(DS.Anim.smooth, value: filled)
    }

    // MARK: - Helpers
    private func flagEmoji(for dialingCode: String) -> String {
        let code = KuwaitPhone.normalizeDigits(dialingCode).filter(\.isNumber)
        guard let iso = dialingToISO[code], iso.count == 2 else { return "\u{1F310}" }
        return isoToFlag(iso) ?? "\u{1F310}"
    }

    private func isoToFlag(_ isoCode: String) -> String? {
        let upper = isoCode.uppercased()
        guard upper.count == 2 else { return nil }
        let base: UInt32 = 127397
        var scalars = String.UnicodeScalarView()
        for scalar in upper.unicodeScalars {
            guard let flagScalar = UnicodeScalar(base + scalar.value) else { return nil }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }

    private var dialingToISO: [String: String] {
        [
            "1": "US", "7": "RU", "20": "EG", "27": "ZA", "30": "GR",
            "31": "NL", "32": "BE", "33": "FR", "34": "ES", "36": "HU",
            "39": "IT", "40": "RO", "41": "CH", "43": "AT", "44": "GB",
            "45": "DK", "46": "SE", "47": "NO", "48": "PL", "49": "DE",
            "51": "PE", "52": "MX", "53": "CU", "54": "AR", "55": "BR",
            "56": "CL", "57": "CO", "58": "VE", "60": "MY", "61": "AU",
            "62": "ID", "63": "PH", "64": "NZ", "65": "SG", "66": "TH",
            "81": "JP", "82": "KR", "84": "VN", "86": "CN", "90": "TR",
            "91": "IN", "92": "PK", "93": "AF", "94": "LK", "95": "MM",
            "98": "IR", "212": "MA", "213": "DZ", "216": "TN", "218": "LY",
            "220": "GM", "221": "SN", "222": "MR", "223": "ML", "224": "GN",
            "225": "CI", "226": "BF", "227": "NE", "228": "TG", "229": "BJ",
            "230": "MU", "231": "LR", "232": "SL", "233": "GH", "234": "NG",
            "235": "TD", "236": "CF", "237": "CM", "238": "CV", "239": "ST",
            "240": "GQ", "241": "GA", "242": "CG", "243": "CD", "244": "AO",
            "245": "GW", "246": "IO", "248": "SC", "249": "SD", "250": "RW",
            "251": "ET", "252": "SO", "253": "DJ", "254": "KE", "255": "TZ",
            "256": "UG", "257": "BI", "258": "MZ", "260": "ZM", "261": "MG",
            "262": "RE", "263": "ZW", "264": "NA", "265": "MW", "266": "LS",
            "267": "BW", "268": "SZ", "269": "KM", "290": "SH", "297": "AW",
            "298": "FO", "299": "GL", "350": "GI", "351": "PT", "352": "LU",
            "353": "IE", "354": "IS", "355": "AL", "356": "MT", "357": "CY",
            "358": "FI", "359": "BG", "370": "LT", "371": "LV", "372": "EE",
            "373": "MD", "374": "AM", "375": "BY", "376": "AD", "377": "MC",
            "378": "SM", "380": "UA", "381": "RS", "382": "ME", "383": "XK",
            "385": "HR", "386": "SI", "387": "BA", "389": "MK", "420": "CZ",
            "421": "SK", "423": "LI", "500": "FK", "501": "BZ", "502": "GT",
            "503": "SV", "504": "HN", "505": "NI", "506": "CR", "507": "PA",
            "508": "PM", "509": "HT", "590": "GP", "591": "BO", "592": "GY",
            "593": "EC", "594": "GF", "595": "PY", "596": "MQ", "597": "SR",
            "598": "UY", "599": "CW", "670": "TL", "672": "NF", "673": "BN",
            "674": "NR", "675": "PG", "676": "TO", "677": "SB", "678": "VU",
            "679": "FJ", "680": "PW", "681": "WF", "682": "CK", "683": "NU",
            "685": "WS", "686": "KI", "687": "NC", "688": "TV", "689": "PF",
            "690": "TK", "691": "FM", "692": "MH", "850": "KP", "852": "HK",
            "853": "MO", "855": "KH", "856": "LA", "880": "BD", "886": "TW",
            "960": "MV", "961": "LB", "962": "JO", "963": "SY", "964": "IQ",
            "965": "KW", "966": "SA", "967": "YE", "968": "OM", "970": "PS",
            "971": "AE", "972": "IL", "973": "BH", "974": "QA", "975": "BT",
            "976": "MN", "977": "NP", "992": "TJ", "993": "TM", "994": "AZ",
            "995": "GE", "996": "KG", "998": "UZ"
        ]
    }
}
