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
    /// نقاط الخطوات داخل المربّع (`DSMotionRules.SignupStep`) — nil = بلا نقاط («استكمال التسجيل»)
    var step: Int? = nil
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
                        VStack(spacing: DS.Spacing.md) {
                            // النقاط ثابتة في المربّع والمحتوى ينزلق تحتها (A1)
                            if let step {
                                SignupStepDots(count: DSMotionRules.signupStepCount, current: step)
                            }
                            content()
                        }
                            .padding(DS.Spacing.lg)
                            .frame(maxWidth: DS.Landscape.alertMaxWidth)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous)
                                .fill(DS.Color.surface))
                            .dsCardShadow()
                            // المربّع يظهر مرة بتكبير هادئ من ٠٫٩٤ مع تلاشٍ (نابض المربّعات) — «تقليل الحركة»: تلاشٍ
                            .dsEntrance(delay: DSMotion.iconDelay, scale: DSMotion.panelScale,
                                        animation: DSMotion.panel, anchor: .center)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == current ? DS.Color.accentLight : i < current ? DS.Color.primary : DS.Color.cardBorder)
                    .frame(width: i == current ? DS.Spacing.lg : DS.Spacing.xsm, height: DS.Spacing.xsm)
            }
        }
        // الكبسولة الذهبية تنتقل للخطوة التالية مع انزلاق المربّع — «تقليل الحركة»: تتبدّل مباشرة
        .animation(reduceMotion ? nil : DSMotion.stepIn, value: current)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t("الخطوة \(current + 1) من \(count)", "Step \(current + 1) of \(count)"))
    }
}

/// علامة المختار على ركن المربّع الكبير: ✓ ذهبية في قرص — الاختيار واضح لا باللون وحده
struct SignupCheckBadge: View {
    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .dsGlyph(DS.Glyph.xl, weight: .semibold)
            .foregroundColor(DS.Color.accentLight)
            .background(Circle().fill(DS.Color.surface))
            .padding(DS.Spacing.xs)
            .transition(.scale(scale: DSMotionRules.tilePopScale).combined(with: .opacity))
            .accessibilityHidden(true)
    }
}

// MARK: - التدفّق

struct SignupOriginFlow: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var origin: SignupOriginRules.Origin?
    /// اتجاه آخر انتقال — يُضبط قبل التبديل فيخرج المربّع القديم في الجهة الصحيحة
    @State private var forward = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Step = DSMotionRules.SignupStep

    private func step(_ o: SignupOriginRules.Origin?) -> Step { o == nil ? .choose : .form }

    var body: some View {
        let transition = AnyTransition.dsStep(forward: forward,
                                              rtl: LanguageManager.shared.layoutDirection == .rightToLeft,
                                              reduceMotion: reduceMotion)
        SignupBoxShell(subtitle: L10n.t(SignupText.chooseTitle, "Registration"), step: step(origin).rawValue,
                       onSignOut: { Task { await authVM.signOut() } }) {
            // فوق بعض أثناء الانتقال (لا يتكدّسان عمودياً)
            ZStack(alignment: .top) {
                if let origin {
                    AnyView(SignupFormBox(origin: origin) { go(to: nil) })
                        .transition(transition)
                } else {
                    AnyView(SignupChooseBox { o in go(to: o) })
                        .transition(transition)
                }
            }
        }
    }

    /// إلى الأمام (الخيار ← البيانات) أو الرجوع: الاتجاه أولاً بلا حركة، ثم التبديل في الدورة التالية
    private func go(to new: SignupOriginRules.Origin?) {
        forward = DSMotionRules.isForward(from: step(origin).rawValue, to: step(new).rawValue)
        DispatchQueue.main.async {
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.stepIn) { origin = new }
        }
    }
}

// MARK: - ١) الخياران

struct SignupChooseBox: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onChoose: (SignupOriginRules.Origin) -> Void
    /// المربّع المختار: يقفز ويُطوَّق بالذهبي لحظةً ثم ينتقل (A1)
    @State private var picked: SignupOriginRules.Origin?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t(SignupText.chooseBoxTitle, "Tell us how you're related to the family"))
                .dsFont(.headline).foregroundColor(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // مربّعان كبيران جنباً إلى جنب — فوق بعض من أحجام إمكانية الوصول
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DS.Spacing.sm)) : AnyLayout(HStackLayout(spacing: DS.Spacing.sm))
            layout {
                tile(L10n.t(SignupText.fromFamily, "From the family"), icon: "tree.fill", tint: DS.Color.primaryFill,
                     origin: .family)
                tile(L10n.t(SignupText.fromOutside, "From outside the family"), icon: "link", tint: DS.Color.palmFill,
                     origin: .outside)
            }
        }
    }

    /// مربّع: قرص الرمز فوق والعنوان تحته — بلا نص فرعي (المالك)
    private func tile(_ title: String, icon: String, tint: Color, origin: SignupOriginRules.Origin) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
        let selected = picked == origin
        return Button {
            // ضغطة واحدة: يُطوَّق ويقفز، ثم ينتقل بعد لحظة (فوراً مع «تقليل الحركة»)
            guard picked == nil else { return }
            picked = origin
            DispatchQueue.main.asyncAfter(deadline: .now() + DSMotionRules.selectHold(reduceMotion: reduceMotion)) {
                onChoose(origin)
            }
        } label: {
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
            .background(shape.fill(selected ? DS.Color.cardBackgroundSoft : DS.Color.cardBackground))
            .overlay(shape.strokeBorder(selected ? DS.Color.accentLight : DS.Color.cardBorder,
                                        lineWidth: selected ? DS.Border.width * 2 : DS.Border.width))
            .overlay(alignment: .topTrailing) { if selected { SignupCheckBadge() } }
            .animation(DSMotion.tap, value: selected)
            .dsSelectPop(selected)
            .contentShape(shape)
        }
        // ضغطة المربّعات الموحّدة (تصغير ٠٫٩٧ في ١٢٠ م.ث؛ «تقليل الحركة» بلا تصغير)
        .buttonStyle(AdminTilePressStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
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
    /// صورة الذكر (اختيارية) — تُسقط إن تحوّل الجنس إلى «أنثى»
    @State private var photo: UIImage?
    /// الخطأ تحت الحقل يظهر بعد أن يتوقّف العضو عن الكتابة (لا مع كل حرف)
    @State private var nameSettled = true
    @State private var familySettled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias R = SignupOriginRules

    private var age: Int? {
        guard birthDateChosen else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: Date()).year
    }
    private var missing: [SignupOriginRules.Field] {
        R.missingFields(origin: origin, name: fullName, family: familyName, birthChosen: birthDateChosen, age: age, gender: gender)
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
            // صورة كبيرة للذكور فقط (المالك ٢٠٢٦-١١-٢٧) — تختفي مع «أنثى»: النساء بلا صور
            if R.showsPhoto(gender: gender) {
                DSProfilePhotoPicker(selectedImage: $photo, enableCrop: true, cropShape: .circle,
                                     title: L10n.t("الصورة الشخصية", "Profile Photo"),
                                     trailing: L10n.t(SignupText.photoOptional, "Optional"),
                                     avatarSize: DS.Icon.signupPhoto,
                                     emptyActionTitle: L10n.t(SignupText.addPhoto, "Add photo"))
                    .transition(.dsReveal(reduceMotion: reduceMotion))
            }
            ForEach(Array(R.fields(origin).enumerated()), id: \.offset) { _, field in
                fieldView(field)
            }
            // لماذا الزرّ معطّل: ما ينقص بأسمائه (يختفي حين يكتمل)
            if !missing.isEmpty {
                let labels = SignupText.fieldLabels(origin)
                let names = missing.compactMap { f in R.fields(origin).firstIndex(of: f).map { labels[$0] } }
                Label {
                    Text(L10n.t(SignupText.missingLine(names), "To send, complete: " + names.joined(separator: ", ")))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle").dsGlyph(DS.Glyph.sm)
                }
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textSecondary)
                .transition(.dsReveal(reduceMotion: reduceMotion))
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
        .animation(reduceMotion ? DSMotion.fade : DSMotion.reveal, value: missing.isEmpty)
        .onChange(of: fullName) { _ in settle(.name) }
        .onChange(of: familyName) { _ in settle(.family) }
        .onChange(of: gender) { g in
            guard !R.showsPhoto(gender: g) else { return }
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.revealOut) { photo = nil }
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
                                placeholder: L10n.t(origin == .outside ? SignupText.outsideNameExample : SignupText.familyNameExample,
                                                    origin == .outside ? "e.g. Mohammad Hassan Hussain" : "e.g. Mohammad Abdullah Ali Ahmad"),
                                text: $fullName, limit: 100, required: true)
                if nameSettled, let e = R.nameError(fullName, origin: origin) {
                    fieldError(e, english: origin == .outside ? "Write the full three-part name." : "Write at least your first and father's name.")
                }
                hint(L10n.t(origin == .outside ? SignupText.outsideNameHint : SignupText.familyNameHint,
                            origin == .outside ? "First, father's and grandfather's name, without the family name."
                                               : "Family Al-Mohammad Ali; the admins link you to your father after checking."))
            }
        case .family:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSComposerField(icon: "person.2.fill", label: L10n.t(SignupText.familyName, "Family"),
                                placeholder: L10n.t(SignupText.familyPlaceholder, "e.g. Al-Mousa"),
                                text: $familyName, limit: 50, required: true)
                if familySettled, let e = R.familyError(familyName) {
                    fieldError(e, english: "Write the family name (at least two letters).")
                }
            }
        case .birth:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSDateFieldRow(icon: "calendar", title: L10n.t(SignupText.birthDate, "Birth date") + " *",
                               hasDate: birthDateChosen, dateText: DSDateText.display(birthDate)) {
                    dsPresentDatePicker(title: L10n.t(SignupText.birthDate, "Birth date"),
                                        initial: birthDate, allowClear: false) { picked in
                        guard let picked else { return }
                        withAnimation(reduceMotion ? DSMotion.fade : DSMotion.reveal) {
                            birthDate = picked
                            birthDateChosen = true
                        }
                    }
                }
                // الملاحظة تنكشف تحت التاريخ بهدوء (A1)
                if let a = age, a < 13 {
                    hint(L10n.t(SignupText.under13, "Accounts can't be created for children under 13."), error: true)
                        .transition(.dsReveal(reduceMotion: reduceMotion))
                } else if let a = age, a < 18 {
                    hint(L10n.t(SignupText.guardian, "The account needs a guardian's approval before activation."))
                        .transition(.dsReveal(reduceMotion: reduceMotion))
                }
            }
        case .gender:
            DSGenderPicker(selection: $gender, required: true, buttons: true, check: true)
        }
    }

    /// خطأ تحت الحقل: رمز + جملة رسمية حمراء (لا باللون وحده)، ينكشف بهدوء
    private func fieldError(_ arabic: String, english: String) -> some View {
        Label {
            Text(L10n.t(arabic, english)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill").dsGlyph(DS.Glyph.sm)
        }
        .dsFont(.footnote)
        .foregroundColor(DS.Color.error)
        .transition(.dsReveal(reduceMotion: reduceMotion))
    }

    private enum Settle { case name, family }

    /// بعد الكتابة: يخفي الخطأ فوراً، ويعيد فحصه بعد مهلة قصيرة إن لم تتغيّر الكتابة (`DSMotionRules.Timing.settle`)
    private func settle(_ field: Settle) {
        let snapshot = field == .name ? fullName : familyName
        if field == .name { nameSettled = false } else { familySettled = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + DSMotionRules.Timing.settle) {
            let now = field == .name ? fullName : familyName
            guard now == snapshot else { return }
            withAnimation(reduceMotion ? DSMotion.fade : DSMotion.reveal) {
                if field == .name { nameSettled = true } else { familySettled = true }
            }
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
        let image = R.photoToSend(photo, gender: g)
        Task {
            await authVM.registerNewUser(firstName: name, familyName: family, birthDate: b, gender: g,
                                         avatarImage: image, outsideFamily: outside)
            // لحظة النجاح (علامة صح صغيرة + اهتزاز نجاح) فوق مربّع «قيد المراجعة» الداخل — لا تظهر مع خطأ
            if authVM.registrationError == nil, authVM.status == .pendingApproval {
                DSMomentToast.show(L10n.t(SignupText.sentMoment, "Request sent"), moment: .success, section: nil)
            }
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
