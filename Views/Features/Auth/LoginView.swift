import SwiftUI
import Combine

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFieldFocused: Bool

    @State private var timeRemaining = 0
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: CGFloat = 0
    @State private var bgRotation: Double = 0
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var phoneCaretOffset: CGFloat {
        CGFloat(min(authVM.phoneNumber.count, 15)) * 15.5
    }

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

                // فوتر
                Text(L10n.t("تطبيق خاص لأفراد العائلة فقط", "Private app for family members only"))
                    .font(DS.Font.caption1)
                    .foregroundColor(.secondary)
                    .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: authVM.isOtpSent)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.55).delay(0.15)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                bgRotation = 360
            }
        }
        .onReceive(timer) { _ in
            if timeRemaining > 0 { timeRemaining -= 1 }
        }
    }

    // MARK: - Background
    private var backgroundView: some View {
        Color(UIColor.systemBackground).ignoresSafeArea()
    }

    // MARK: - Logo — Minimal
    private var logoSection: some View {
        VStack(spacing: DS.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: 100, height: 100)

                Text("🌳")
                    .font(.system(size: 54))
            }
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
            .padding(.bottom, DS.Spacing.sm)

            VStack(spacing: DS.Spacing.xs) {
                Text(L10n.t("عائلة المحمد علي", "Al-Muhammad Ali Family"))
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundColor(.primary)

                Text(L10n.t("مرحباً بك في تطبيق شجرة العائلة", "Welcome to the Family Tree App"))
                    .font(DS.Font.subheadline)
                    .foregroundColor(.secondary)
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
                    Text(flagEmoji(for: authVM.dialingCode)).font(.system(size: 20))
                    TextField("+965", text: countryCodeBinding)
                        .keyboardType(.phonePad)
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                }
                .frame(width: 80)

                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(UIColor.separator))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, DS.Spacing.xs)

                ZStack(alignment: .leading) {
                    if authVM.phoneNumber.isEmpty {
                        Text("رقم الهاتف المحمول")
                            .font(DS.Font.subheadline)
                            .foregroundStyle(Color(UIColor.placeholderText))
                    } else {
                        Text(authVM.phoneNumber)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .allowsHitTesting(false)
                    }

                    TextField("", text: phoneBinding)
                        .keyboardType(.numberPad)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.clear)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .tint(DS.Color.accent)
                        .focused($isFieldFocused)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 56)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(
                        isFieldFocused
                            ? DS.Color.accent
                            : Color.clear,
                        lineWidth: isFieldFocused ? 1.5 : 0
                    )
            )
            .animation(DS.Anim.quick, value: isFieldFocused)

            // زر الإرسال — Compact
            Button {
                isFieldFocused = false
                timeRemaining = 60
                Task {
                    await authVM.sendOTP()
                    if !authVM.isOtpSent { timeRemaining = 0 }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    if authVM.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(timeRemaining > 0
                             ? L10n.t("إعادة الطلب بعد \(timeRemaining)ث", "Resend in \(timeRemaining)s")
                             : L10n.t("متابعة", "Continue"))
                            .font(DS.Font.calloutBold)
                        Image(systemName: "arrow.left")
                            .font(.system(size: 14, weight: .bold))
                            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DS.Color.accent.opacity(isDisabled ? 0.5 : 1.0))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .buttonStyle(DSScaleButtonStyle())
            .disabled(isDisabled)
        }
        .padding(DS.Spacing.lg)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(DS.Radius.lg)
        .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 5)
    }

    // MARK: - OTP Input — Compact Card
    @ViewBuilder
    var otpInputSection: some View {
        let isOtpValid = authVM.otpCode.count == 6
        let isLoading = authVM.isLoading
        let otpDisabled = !isOtpValid || isLoading

        VStack(spacing: DS.Spacing.xl) {
            VStack(spacing: DS.Spacing.sm) {
                // أيقونة القفل — Subtle
                ZStack {
                    Circle()
                        .fill(Color(UIColor.secondarySystemBackground))
                        .frame(width: 46, height: 46)

                    Image(systemName: "lock.shield")
                        .font(.system(size: 20, weight: .light))
                        .foregroundColor(.primary)
                }

                Text(L10n.t("رمز التحقق", "Verification Code"))
                    .font(DS.Font.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: DS.Spacing.xs) {
                    Text(L10n.t("أرسلنا رمزاً إلى", "Code sent to"))
                        .font(DS.Font.caption1)
                        .foregroundColor(.secondary)
                    Text("\(authVM.dialingCode)\(authVM.phoneNumber)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(DS.Color.accent)
                    
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
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, DS.Spacing.xs)
                }
            }

            // حقل OTP — Clean minimal style
            TextField("------", text: otpBinding)
                .keyboardType(.numberPad)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .tracking(12)
                .frame(height: 60)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(
                            isFieldFocused ? DS.Color.accent : Color.clear,
                            lineWidth: isFieldFocused ? 1.5 : 0
                        )
                )
                .focused($isFieldFocused)
                .onAppear { isFieldFocused = true }
                .onChange(of: authVM.otpCode) { _, newValue in
                    if newValue.count == 6 { Task { await authVM.verifyOTP() } }
                }

            VStack(spacing: DS.Spacing.md) {
                // زر التأكيد — Elegant
                Button {
                    Task { await authVM.verifyOTP() }
                } label: {
                    HStack {
                        if authVM.isLoading { ProgressView().tint(.white) }
                        else {
                            Text(L10n.t("تأكيد الدخول", "Verify"))
                                .font(DS.Font.calloutBold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DS.Color.accent.opacity(otpDisabled ? 0.5 : 1.0))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .buttonStyle(DSScaleButtonStyle())
                .disabled(otpDisabled)
            }

            statusMessage
        }
        .padding(DS.Spacing.lg)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(DS.Radius.lg)
        .shadow(color: .black.opacity(0.05), radius: 15, x: 0, y: 5)
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let error = authVM.otpErrorMessage {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DS.Color.error)
                    .font(.system(size: 16, weight: .bold))
                Text(error)
                    .font(DS.Font.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.error)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.error.opacity(0.12))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
        } else if !authVM.otpStatusMessage.isEmpty {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(DS.Color.success)
                    .font(.system(size: 16, weight: .bold))
                Text(authVM.otpStatusMessage)
                    .font(DS.Font.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.success)
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
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
