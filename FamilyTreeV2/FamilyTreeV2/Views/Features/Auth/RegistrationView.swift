import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var fullName: String = ""
    /// «من العائلة» (R1، المالك ٢٠٢٦-١١-٢٧): العائلة «المحمدعلي» ضمناً — لا اختيار للعائلة ولا للوالد؛
    /// الإدارة تربطه بعد التحقق من اسم والده في الشجرة («ربط بالشجرة» / «ربط بشجرة النساء»)
    private let familyName = SignupOriginRules.familyName
    /// مسافة علوية إضافية — تستخدمها المعاينة حتى لا يغطّي شريطها المحتوى
    var topInset: CGFloat = 0
    /// الرجوع إلى «التسجيل» (الخياران «من العائلة / من خارج العائلة»، R1) — nil = بلا رجوع كما كان
    var onBack: (() -> Void)? = nil

    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    /// اختار تاريخه فعلاً؟ — وإلا لا يُحفظ تاريخ «قبل ٢٠ سنة» الافتراضي كأنه تاريخ ميلاده (حدث ٢٠٢٦-١٠-٠٥)
    @State private var birthDateChosen = false
    /// الجنس مطلوب بلا اختيار مسبق (الدفعة ١٢ — كان «ذكر» ثابتاً فيُسجَّل كل منضم ذكراً): «male» أو «female»
    @State private var selectedGender: String = ""
    @State private var selectedImage: UIImage? = nil
    /// الصورة اختيارية للجميع (قرار المالك ٢٠٢٦-١٠-٢٨، المراجعة الثانية) — لا تمنع الإرسال أبداً
    private var photoMissing: Bool { false }

    // Animation states
    @State private var headerScale: CGFloat = 0.8
    @State private var headerOpacity: CGFloat = 0
    @State private var hasAttemptedSubmit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showConfirmSubmit = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                AnyView(topBar)

                ScrollView(showsIndicators: false) {
                    // مسافات أضيق (طلب المالك ٢٠٢٦-١٠-١٩ «أبسط»)
                    VStack(spacing: DS.Spacing.lg) {
                        if topInset > 0 { Color.clear.frame(height: topInset) }
                        // الصورة الشخصية — في الأعلى مثل حسابي
                        // لا صور للإناث (قاعدة المالك ٢٠٢٦-١١-١٧) — الخانة تختفي عند اختيار «أنثى»، والسيرفر يفرّغ أي صورة لأنثى
                        if selectedGender != "female" {
                            AnyView(photoSection)
                                .scaleEffect(headerScale)
                                .opacity(headerOpacity)
                        }

                        // الحقول — بطاقة القسم الواحدة وحقول المربّعات (نفس «تسجيل عضو جديد» في الإدارة)،
                        // تدخل بعد الصورة: البيانات ← زر الإرسال
                        VStack(spacing: DS.Spacing.md) {
                            // بلا شارة «مطلوب» — الحقول المطلوبة عليها النجمة الحمراء
                            DSComposerSection(title: L10n.t("البيانات الأساسية", "Basic Info"),
                                              icon: "person.text.rectangle.fill",
                                              tint: DS.Color.primary,
                                              index: 0) {
                                // كل حقل خلف AnyView — مكدس iOS 16 (انظر RootView)
                                AnyView(nameFieldSection)
                                AnyView(birthDateSection)
                                AnyView(genderSection)
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)

                        // زر الإرسال
                        AnyView(submitButton)
                            .dsStaggerIn(2)
                    }
                    // الحقول تبدأ بعد الصورة (نفس «بعد الرأس» في المربّعات)
                    .environment(\.dsStaggerBase, DSMotion.sectionsAfterHeader)
                    // وضع العرض: النموذج بعمود قراءة متوسّط
                    .dsLandscapeReadable()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(
            L10n.t("تعذّر التسجيل", "Registration Failed"),
            isPresented: Binding(
                get: { authVM.registrationError != nil },
                set: { if !$0 { authVM.registrationError = nil } }
            )
        ) {
            Button(L10n.t("حسناً", "OK")) { authVM.registrationError = nil }
        } message: {
            Text(authVM.registrationError ?? "")
        }
        .onAppear {
            Log.info("[REGISTRATION] RegistrationView ظهرت — البروفايل غير موجود. phone=\(Log.masked(authVM.phoneNumber))")
            // «تقليل الحركة»: الصورة تظهر بتلاشٍ فقط بلا تكبير
            guard !reduceMotion else {
                headerScale = 1.0
                withAnimation(DSMotion.fade) { headerOpacity = 1.0 }
                return
            }
            withAnimation(DS.Anim.elastic.delay(0.2)) {
                headerScale = 1.0
                headerOpacity = 1.0
            }
        }
    }

    // MARK: - Top Bar — الرأس الملوّن الموحّد للصفحات الفرعية (كان نسخة يدوية بشريط سدو قديم)
    private var topBar: some View {
        DSSubPageHeader(title: L10n.t(SignupOriginRules.Ar.chooseTitle, "Registration"),
                        subtitle: L10n.t(SignupOriginRules.Ar.fromFamily, "From the family"),
                        icon: "person.badge.plus",
                        nav: onBack == nil ? .none : .back,
                        onBack: onBack) {
            // تسجيل الخروج — بزرّ الرأس الموحّد في موضع الإغلاق
            DSHeaderButton(symbol: "rectangle.portrait.and.arrow.right",
                           label: L10n.t("تسجيل الخروج", "Sign out")) {
                Task { await authVM.signOut() }
            }
        }
    }

    // MARK: - Photo Section — كاميرا على الصورة مباشرة
    /// دائرة أصغر (٨٨) وتحتها «اختياري» فقط (طلب المالك ٢٠٢٦-١٠-١٩ «أبسط»)
    private var photoSection: some View {
        VStack(spacing: DS.Spacing.xs) {
            DSProfilePhotoPicker(
                selectedImage: $selectedImage,
                enableCrop: true,
                cropShape: .circle,
                title: L10n.t("الصورة الشخصية", "Profile Photo"),
                trailing: L10n.t("اختيارية", "Optional"),
                compactEmptyState: true,
                avatarSize: DS.Icon.photoPickerCompact
            )
        }
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - العمر (الشروط ٢٠٢٦-١٠-٢٨): دون ١٣ لا حساب، و١٣–١٧ بموافقة ولي الأمر

    private var age: Int? {
        guard birthDateChosen else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year], from: birthDate, to: Date()).year
    }
    private var isUnder13: Bool { (age ?? 99) < 13 }
    private var needsGuardian: Bool { guard let a = age else { return false }; return a >= 13 && a < 18 }

    // MARK: - Name Field — الاسم الرباعي
    private var nameFieldSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // حقل المربّعات الموحّد (كان `DSTextField` القديم)
            DSComposerField(
                icon: "person.fill",
                label: L10n.t(SignupOriginRules.Ar.familyFullName, "Full Name (4 parts)") + " " + L10n.t("(باللغة العربية)", "(in Arabic)"),
                placeholder: L10n.t("محمد عبدالله علي أحمد", "Mohammad Abdullah Ali Ahmad"),
                text: $fullName,
                tint: DS.Color.primary,
                required: true
            )
            .onChange(of: fullName) { _ in
                if fullName.count > 100 {
                    fullName = String(fullName.prefix(100))
                }
            }

            // العائلة «المحمدعلي» ضمناً، والربط بالوالد تتحقق منه الإدارة
            Text(L10n.t(SignupOriginRules.Ar.familyNameHint, "Family: Al-Mohammad Ali. The admins link you to your father after checking his name in the tree."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if hasAttemptedSubmit && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("الاسم مطلوب", "Name is required"))
            }
        }
    }

    // MARK: - Birth Date — صفّ تاريخ يفتح مربّع التاريخ الموحّد بالمنتصف (نفس «تسجيل عضو جديد»)
    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // صفّ التاريخ الموحّد (`DSDateFieldRow`، طلب المالك ٢٠٢٦-١١-١٠) — مطلوب، فلا «بدون تاريخ»
            DSDateFieldRow(icon: "calendar", title: L10n.t("تاريخ الميلاد", "Birth Date") + " *",
                           hasDate: birthDateChosen, dateText: DSDateText.display(birthDate)) {
                dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                    initial: birthDate, allowClear: false) { picked in
                    guard let picked else { return }
                    birthDate = picked
                    birthDateChosen = true
                }
            }

            if hasAttemptedSubmit && !birthDateChosen {
                validationError(L10n.t("تاريخ الميلاد مطلوب", "Birth date is required"))
            }
            if isUnder13 && birthDateChosen {
                validationError(L10n.t("لا يمكن إنشاء حساب لمن هم دون الثالثة عشرة. يمكن لولي أمرك إضافتك إلى شجرة العائلة.",
                                       "Accounts can't be created for children under 13. Your guardian can add you to the family tree."))
                    .fixedSize(horizontal: false, vertical: true)
            } else if needsGuardian {
                DSNoteCard(L10n.t("حسابك يحتاج موافقة ولي أمرك من حسابه في التطبيق قبل تفعيله.",
                                  "Your account needs your guardian's approval from their account in the app before it is activated."),
                           icon: "person.2.fill", tint: DS.Color.info)
            }
        }
    }

    // MARK: - Gender — اختيار الجنس الموحّد (مطلوب، بلا اختيار مسبق — الدفعة ١٢)
    private var genderSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            DSGenderPicker(selection: $selectedGender, required: true)

            if hasAttemptedSubmit && selectedGender.isEmpty {
                validationError(L10n.t("اختيار الجنس مطلوب", "Choosing a gender is required"))
            }
        }
        // الأنثى بلا صورة — تُمسح المختارة قبل التبديل
        .onChange(of: selectedGender) { g in
            if g == "female" { selectedImage = nil }
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        VStack(spacing: DS.Spacing.sm) {
            let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            // Validation أقوى: طول 2-50 + على الأقل حرفان أبجديان (يرفض "12" أو "...")
            let fullLetterCount = trimmedFull.filter { $0.isLetter }.count
            let familyLetterCount = trimmedFamily.filter { $0.isLetter }.count
            let isValid = trimmedFull.count >= 2 && trimmedFull.count <= 50 && fullLetterCount >= 2
                       && trimmedFamily.count >= 2 && trimmedFamily.count <= 50 && familyLetterCount >= 2
                       && !selectedGender.isEmpty
                       && birthDateChosen && !isUnder13
            let isDisabled = !isValid || authVM.isLoading

            DSPrimaryButton(
                L10n.t("إرسال طلب الانضمام", "Submit Join Request"),
                icon: "paperplane.fill",
                isLoading: authVM.isLoading,
                useGradient: !isDisabled,
                color: isDisabled ? DS.Color.inactive : DS.Color.primary
            ) {
                withAnimation(DS.Anim.snappy) { hasAttemptedSubmit = true }
                guard isValid else { return }
                showConfirmSubmit = true
            }
            .disabled(authVM.isLoading)
            // معطّل ظاهرياً حتى تكتمل الحقول المطلوبة (ومنها الجنس) — الضغط يُظهر الناقص ولا يُرسل
            .opacity(isValid || authVM.isLoading ? 1 : DS.Opacity.disabled)
            .accessibilityHint(isValid ? "" : L10n.t("أكمل الحقول المطلوبة أولاً", "Complete the required fields first"))
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xxl)
            // تأكيد الإرسال — مربّع التطبيق الموحّد بالمنتصف بدل القائمة السفلية
            .dsAlert(
                L10n.t("تأكيد إرسال الطلب", "Confirm Submission"),
                isPresented: $showConfirmSubmit
            ) {
                Button(L10n.t("مراجعة البيانات", "Review"), role: .cancel) {}
                Button(L10n.t("إرسال", "Submit")) {
                    Task {
                        await authVM.registerNewUser(
                            firstName: trimmedFull,
                            familyName: trimmedFamily,
                            birthDate: birthDate,
                            gender: selectedGender,
                            avatarImage: selectedGender == "female" ? nil : selectedImage
                        )
                    }
                }
            } message: {
                let composed = "\(FamilyNameCatalog.stripTrailingFamily(trimmedFull, chosen: trimmedFamily)) \(trimmedFamily)"
                Text(L10n.t(
                    "اسمك: \(composed)\nسيُرسل طلبك للإدارة وتنتظر الموافقة.",
                    "Name: \(composed)\nYour request will be sent to admins for approval."
                ))
            }
        }
    }

    // MARK: - Validation Error
    private func validationError(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .dsGlyph(DS.Glyph.smCompact)
            Text(text)
                .dsFont(.caption)
        }
        .foregroundColor(DS.Color.error)
        .padding(.leading, DS.Spacing.sm)
        // «تقليل الحركة»: تلاشٍ فقط بلا انزلاق
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }
}
