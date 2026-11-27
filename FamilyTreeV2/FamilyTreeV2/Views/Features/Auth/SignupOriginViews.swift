import SwiftUI

// MARK: - «التسجيل» بمربّعات صغيرة (موافقة المالك ٢٠٢٦-١١-٢٧، الوحدة R1 — boxes.png)
//
// بعد رمز الدخول (`authenticatedNoProfile`): مربّعان في منتصف الشاشة فوق خلفية كحلية/رملية:
//  ١) «يُرجى تحديد صلتك بالعائلة»: مربّعا «من العائلة» و«من خارج العائلة» جنباً إلى جنب، بلا نص فرعي، والضغط ينقل مباشرة.
//  ٢) مربّع واحد بالحقول (`SignupOriginRules.fields`) و«إرسال الطلب إلى الإدارة» مباشرة ← `registerNewUser` ← مربّع
//     «قيد المراجعة» (`WaitingForApprovalView`). «من العائلة»: بلا اختيار الوالد — الإدارة تربط في «الوارد».
// الصدفة المشتركة (`SignupBoxShell`) يستعملها أيضاً «قيد المراجعة» و«استكمال التسجيل». القواعد والنصوص: `SignupOriginRules`.

typealias SignupText = SignupOriginRules.Ar

// MARK: - الصدفة: رأس كحلي باسم العائلة، أرضية رملية، والمربّع في المنتصف

struct SignupBoxShell<Content: View>: View {
    var subtitle: String
    var onSignOut: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle().fill(DS.Color.gradientBand)
                        .frame(height: geo.size.height * 0.45 + geo.safeAreaInsets.top)
                    DS.Color.cardBackgroundSoft
                }
                .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        Spacer(minLength: DS.Spacing.xl)
                        content()
                            .padding(DS.Spacing.lg)
                            .frame(maxWidth: DS.Landscape.alertMaxWidth)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .fill(DS.Color.surface))
                            .dsCardShadow()
                            .padding(.horizontal, DS.Spacing.lg)
                        Spacer(minLength: DS.Spacing.xl)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsLightStatusBar()
    }

    private var header: some View {
        ZStack {
            VStack(spacing: DS.Spacing.xxs) {
                Text(L10n.t(SignupText.brand, "Al-Mohammad Ali family"))
                    .dsFont(.headline).foregroundColor(DS.Color.accentLight)
                Text(subtitle)
                    .dsFont(.caption).foregroundColor(DS.Color.textOnPrimary.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            if let onSignOut {
                HStack {
                    Spacer()
                    DSHeaderButton(symbol: "rectangle.portrait.and.arrow.right",
                                   label: L10n.t(SignupText.signOut, "Sign out"), action: onSignOut)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
    }
}

/// عنوان المربّع: قرص الرمز + العنوان (+ نقاط التقدّم فوقه إن وُجدت)
struct SignupBoxTitle: View {
    let icon: String
    let title: String
    var tint: Color = DS.Color.primaryFill

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Icon.row, height: DS.Icon.row)
                .background(Circle().fill(tint))
                .accessibilityHidden(true)
            Text(title).dsFont(.headline).foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// نقاط التقدّم: الحالية كبسولة ذهبية، السابقة كحلية، اللاحقة رمادية
struct SignupStepDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? DS.Color.accentLight : i < current ? DS.Color.primary : DS.Color.cardBorder)
                    .frame(width: i == current ? DS.Spacing.lg : DS.Spacing.xsm, height: DS.Spacing.xsm)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الخطوة \(current + 1) من \(count)", "Step \(current + 1) of \(count)"))
    }
}

// MARK: - التدفّق

struct SignupOriginFlow: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var origin: SignupOriginRules.Origin?

    var body: some View {
        SignupBoxShell(subtitle: L10n.t(SignupText.chooseTitle, "Registration"),
                       onSignOut: { Task { await authVM.signOut() } }) {
            if let origin {
                AnyView(SignupFormBox(origin: origin) { withAnimation(DSMotion.fade) { self.origin = nil } })
                    .transition(.opacity)
            } else {
                AnyView(SignupChooseBox { o in withAnimation(DSMotion.fade) { origin = o } })
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - ١) الخياران

struct SignupChooseBox: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let onChoose: (SignupOriginRules.Origin) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t(SignupText.chooseBoxTitle, "Tell us how you're related to the family"))
                .dsFont(.headline).foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // مربّعان كبيران جنباً إلى جنب — فوق بعض من أحجام إمكانية الوصول
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm)) : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
            layout {
                tile(L10n.t(SignupText.fromFamily, "From the family"), icon: "tree.fill", tint: DS.Color.primaryFill) {
                    onChoose(.family)
                }
                tile(L10n.t(SignupText.fromOutside, "From outside the family"), icon: "link", tint: DS.Color.palmFill) {
                    onChoose(.outside)
                }
            }
        }
    }

    /// مربّع: قرص الرمز فوق والعنوان تحته — بلا نص فرعي (المالك)
    private func tile(_ title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        return Button(action: action) {
            VStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: DS.Icon.state, height: DS.Icon.state)
                    .background(Circle().fill(tint))
                    .accessibilityHidden(true)
                Text(title).dsFont(.rowTitle).foregroundColor(DS.Color.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget * 3)
            .background(shape.fill(DS.Color.cardBackground))
            .overlay(shape.strokeBorder(DS.Color.cardBorder, lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - ٢) البيانات — مربّع واحد ثم الإرسال مباشرة

struct SignupFormBox: View {
    @EnvironmentObject var authVM: AuthViewModel
    let origin: SignupOriginRules.Origin
    let onBack: () -> Void

    @State private var fullName = ""
    @State private var familyName = ""
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var birthDateChosen = false
    /// مطلوب بلا اختيار مسبق (مثل التسجيل السابق)
    @State private var gender = ""

    private typealias R = SignupOriginRules

    private var age: Int? {
        guard birthDateChosen else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: Date()).year
    }
    private var canSubmit: Bool {
        R.canSubmit(origin: origin, name: fullName, family: familyName, birthChosen: birthDateChosen, age: age, gender: gender)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            SignupBoxTitle(icon: origin == .outside ? "link" : "tree.fill",
                           title: L10n.t(origin == .outside ? SignupText.fromOutside : SignupText.fromFamily,
                                         origin == .outside ? "From outside the family" : "From the family"),
                           tint: origin == .outside ? DS.Color.palmFill : DS.Color.primaryFill)
            ForEach(Array(R.fields(origin).enumerated()), id: \.offset) { _, field in
                fieldView(field)
            }
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t(SignupText.back, "Back"), role: .cancel) { onBack() }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(0)
                DSButton(L10n.t(SignupText.submit, "Send the request to the admins"), isLoading: authVM.isLoading) { submit() }
                    .disabled(!canSubmit || authVM.isLoading)
                    .layoutPriority(1)
            }
        }
        .dsAlert(L10n.t("تعذّر التسجيل", "Registration Failed"),
                 isPresented: Binding(get: { authVM.registrationError != nil },
                                      set: { if !$0 { authVM.registrationError = nil } })) {
            Button(L10n.t("حسناً", "OK")) { authVM.registrationError = nil }
        } message: {
            Text(authVM.registrationError ?? "")
        }
    }

    @ViewBuilder
    private func fieldView(_ f: SignupOriginRules.Field) -> some View {
        switch f {
        case .name:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSComposerField(icon: "person.fill",
                                label: L10n.t(origin == .outside ? SignupText.outsideFullName : SignupText.familyFullName,
                                              origin == .outside ? "Three-part name" : "Full name (4 parts)"),
                                placeholder: L10n.t(origin == .outside ? "محمد حسن حسين" : "محمد عبدالله علي أحمد",
                                                    origin == .outside ? "First, father's and grandfather's name" : "Four-part name"),
                                text: $fullName, limit: 100, required: true)
                hint(L10n.t(origin == .outside ? SignupText.outsideNameHint : SignupText.familyNameHint,
                            origin == .outside ? "First, father's and grandfather's name, without the family name."
                                               : "Family Al-Mohammad Ali; the admins link you to your father after checking."))
            }
        case .family:
            DSComposerField(icon: "person.2.fill", label: L10n.t(SignupText.familyName, "Family"),
                            placeholder: L10n.t(SignupText.familyPlaceholder, "e.g. Al-Mousa"),
                            text: $familyName, limit: 50, required: true)
        case .birth:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSDateFieldRow(icon: "calendar", title: L10n.t(SignupText.birthDate, "Birth date") + " *",
                               hasDate: birthDateChosen, dateText: DSDateText.display(birthDate)) {
                    dsPresentDatePicker(title: L10n.t(SignupText.birthDate, "Birth date"),
                                        initial: birthDate, allowClear: false) { picked in
                        guard let picked else { return }
                        birthDate = picked
                        birthDateChosen = true
                    }
                }
                if let a = age, a < 13 {
                    hint(L10n.t(SignupText.under13, "Accounts can't be created for children under 13."), error: true)
                } else if let a = age, a < 18 {
                    hint(L10n.t(SignupText.guardian, "The account needs a guardian's approval before activation."))
                }
            }
        case .gender:
            DSGenderPicker(selection: $gender, required: true, buttons: true)
        }
    }

    private func hint(_ text: String, error: Bool = false) -> some View {
        Text(text)
            .dsFont(.footnote)
            .foregroundColor(error ? DS.Color.error : DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() {
        guard canSubmit, !authVM.isLoading else { return }
        let name = R.tidy(fullName)
        let family = R.familyToSave(origin: origin, typed: familyName)
        let outside = origin == .outside
        let g = gender
        let b = birthDate
        Task {
            await authVM.registerNewUser(firstName: name, familyName: family, birthDate: b, gender: g, outsideFamily: outside)
        }
    }
}

#if DEBUG
#Preview("التسجيل") {
    SignupOriginFlow()
        .environmentObject(AuthViewModel())
}

#Preview("من خارج العائلة") {
    SignupBoxShell(subtitle: "التسجيل") {
        SignupFormBox(origin: .outside, onBack: {})
    }
    .environmentObject(AuthViewModel())
}
#endif
