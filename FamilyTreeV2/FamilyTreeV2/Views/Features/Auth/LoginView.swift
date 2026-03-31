import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @FocusState private var isFieldFocused: Bool

    @State private var timeRemaining = 0
    @State private var otpTimeRemaining = 0
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: CGFloat = 0




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

    private var otpBinding: Binding<String> {
        Binding(
            get: { authVM.otpCode },
            set: { newValue in
                authVM.otpCode = KuwaitPhone.normalizeDigits(newValue)
                    .filter(\.isNumber)
                    .prefix(6)
                    .map(String.init)
                    .joined()
            }
        )
    }

    var body: some View {
        ZStack {
            // خلفية ديناميكية متحركة
            backgroundView

            VStack(spacing: 0) {
                Spacer()

                // شعار متحرك — Elegant
                logoSection
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                    .padding(.bottom, DS.Spacing.xxxxl)

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
                .frame(maxWidth: 380)
                .padding(.horizontal, DS.Spacing.xl)

                Spacer()
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .animation(DS.Anim.bouncy, value: authVM.isOtpSent)
        .onAppear {
            withAnimation(DS.Anim.elastic.delay(0.15)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
        }
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

    // MARK: - Background
    private var backgroundView: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
        }
    }

    // MARK: - Logo — Royal Gradient
    private var logoSection: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                // Outer glow ring
                Circle()
                    .fill(DS.Color.primary.opacity(0.08))
                    .frame(width: 120, height: 120)

                // Gradient circle
                Circle()
                    .fill(DS.Color.gradientRoyal)
                    .frame(width: 100, height: 100)

                Image(systemName: "leaf.fill")
                    .font(DS.Font.scaled(42, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
            }
            .dsGlowShadow()
            .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: DS.Spacing.xs) {
                Text(L10n.t("عائلة المحمد علي", "Al-Muhammad Ali Family"))
                    .font(DS.Font.title1)
                    .foregroundColor(DS.Color.textPrimary)

                Text(L10n.t("مرحباً بك في تطبيق شجرة العائلة", "Welcome to the Family Tree App"))
                    .font(DS.Font.subheadline)
                    .foregroundColor(DS.Color.textSecondary)
            }
        }
    }

    // MARK: - Phone Input — Compact Card
    @ViewBuilder
    var phoneInputSection: some View {
        let isPhoneValid = authVM.phoneNumber.count >= 6
        let isTimerActive = timeRemaining > 0
        let isLoading = authVM.isLoading
        let isDisabled = !isPhoneValid || isTimerActive || isLoading

        VStack(spacing: DS.Spacing.lg) {
            // حقل الهاتف
            HStack(spacing: 0) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(flagEmoji(for: authVM.dialingCode)).font(DS.Font.scaled(20))
                    TextField("+965", text: countryCodeBinding)
                        .keyboardType(.phonePad)
                        .font(DS.Font.scaled(16, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .frame(width: 80)

                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.Color.textTertiary.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, DS.Spacing.xs)

                PhoneNumberTextField(
                    text: $authVM.phoneNumber,
                    placeholder: L10n.t("رقم الهاتف المحمول", "Mobile Number"),
                    font: .systemFont(ofSize: 20, weight: .bold),
                    keyboardType: .numberPad,
                    maxLength: 15
                )
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 56)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(
                        isFieldFocused
                            ? DS.Color.primary.opacity(0.5)
                            : DS.Color.inactiveBorder,
                        lineWidth: isFieldFocused ? 1.5 : 1
                    )
                    .animation(DS.Anim.quick, value: isFieldFocused)
            )

            // زر الإرسال — DSPrimaryButton
            DSPrimaryButton(
                timeRemaining > 0
                    ? L10n.t("إعادة الطلب بعد \(timeRemaining)ث", "Resend in \(timeRemaining)s")
                    : L10n.t("متابعة", "Continue"),
                icon: timeRemaining > 0 ? nil : "arrow.right",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? DS.Color.inactive : DS.Color.primary
            ) {
                isFieldFocused = false
                timeRemaining = 60
                authVM.otpCode = ""
                Task {
                    await authVM.sendOTP()
                    if !authVM.isOtpSent { timeRemaining = 0 }
                }
            }
            .disabled(isDisabled)

        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.3), lineWidth: 1.5)
        )
        .dsGlowShadow()
    }

    // MARK: - OTP Input — Compact Card
    @ViewBuilder
    var otpInputSection: some View {
        let isOtpValid = authVM.otpCode.count == 6
        let isLoading = authVM.isLoading
        let otpDisabled = !isOtpValid || isLoading

        VStack(spacing: DS.Spacing.xl) {
            VStack(spacing: DS.Spacing.sm) {
                // أيقونة القفل — DSIcon
                DSIcon("lock.shield", color: DS.Color.primary, size: DS.Icon.size, iconSize: 20)

                Text(L10n.t("رمز التحقق", "Verification Code"))
                    .font(DS.Font.headline)
                    .foregroundColor(DS.Color.textPrimary)

                HStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("أرسلنا رمزاً إلى", "Code sent to"))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textSecondary)
                    Text("\(authVM.dialingCode) \(authVM.phoneNumber)")
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundStyle(DS.Color.primary)

                    Button(action: {
                        withAnimation(DS.Anim.smooth) {
                            authVM.isOtpSent = false
                            authVM.otpCode = ""
                            authVM.otpErrorMessage = nil
                            authVM.otpStatusMessage = ""
                            timeRemaining = 0
                        }
                    }) {
                        Image(systemName: "pencil.circle.fill")
                            .font(DS.Font.scaled(16))
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    .padding(.leading, DS.Spacing.xs)
                }

                // مؤقت الرمز — 5 دقائق
                if otpTimeRemaining > 0 {
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: "timer")
                            .font(DS.Font.caption1)
                            .foregroundStyle(otpTimeRemaining <= 60 ? DS.Color.error : DS.Color.primary)
                        Text(L10n.t(
                            "ينتهي الرمز خلال \(otpTimeRemaining / 60):\(String(format: "%02d", otpTimeRemaining % 60))",
                            "Code expires in \(otpTimeRemaining / 60):\(String(format: "%02d", otpTimeRemaining % 60))"
                        ))
                            .font(DS.Font.caption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(otpTimeRemaining <= 60 ? DS.Color.error : DS.Color.primary)
                    }
                    .padding(.top, DS.Spacing.xs)
                } else {
                    Text(L10n.t("انتهت صلاحية الرمز", "Code has expired"))
                        .font(DS.Font.caption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Color.error)
                        .padding(.top, DS.Spacing.xs)
                }
            }

            // حقل OTP — مع تأثير التركيز
            TextField("------", text: otpBinding)
                .keyboardType(.numberPad)
                .font(DS.Font.scaled(32, weight: .bold))
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .tracking(12)
                .frame(height: 60)
                .background(DS.Color.surface)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(
                            isFieldFocused ? DS.Color.primary.opacity(0.5) : DS.Color.inactiveBorder,
                            lineWidth: isFieldFocused ? 1.5 : 1
                        )
                        .animation(DS.Anim.quick, value: isFieldFocused)
                )
                .focused($isFieldFocused)
                .accessibilityLabel(L10n.t("رمز التحقق", "Verification Code"))
                .onAppear {
                    isFieldFocused = true
                    authVM.otpCode = ""
                    otpTimeRemaining = 300
                }
                .onChange(of: authVM.otpCode) { _, newValue in
                    if newValue.count == 6 {
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

            // إعادة طلب الرمز
            Button(action: {
                authVM.otpCode = ""
                authVM.otpErrorMessage = nil
                authVM.otpStatusMessage = ""
                otpTimeRemaining = 300
                Task { await authVM.sendOTP() }
            }) {
                Text(L10n.t("إعادة طلب الرمز", "Resend Code"))
                    .font(DS.Font.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Color.primary)
            }
            .disabled(authVM.isLoading)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.3), lineWidth: 1.5)
        )
        .dsGlowShadow()
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = authVM.otpErrorMessage {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DS.Color.error)
                    .font(DS.Font.scaled(16, weight: .bold))
                Text(error)
                    .font(DS.Font.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.error)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.error.opacity(0.12))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
        } else if !authVM.otpStatusMessage.isEmpty {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DS.Color.success)
                    .font(DS.Font.scaled(16, weight: .bold))
                Text(authVM.otpStatusMessage)
                    .font(DS.Font.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.success)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.success.opacity(0.12))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
        }
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
