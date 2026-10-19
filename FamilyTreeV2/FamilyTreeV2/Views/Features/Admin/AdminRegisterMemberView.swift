import SwiftUI

// MARK: - تسجيل عضو جديد — بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// الرأس الملوّن الموحّد ← صفّ أرقام يتابع اكتمال النموذج ← أقسام المربّعات: الصورة، البيانات
// الأساسية، تاريخ الميلاد، رقم الهاتف ← زر «إضافة العضو» بالزرّ الواحد («أسلوب واحد» ٢٠٢٦-١٠-٠٧).
// منطق النموذج كما هو تماماً: نفس الحقول والحدود والتحقّق والحفظ (`adminAddMember`)
// ورسالتا النجاح والخطأ.
struct AdminRegisterMemberView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss

    @State private var fullName: String = ""
    /// «الاسم الأول» — يتعبّى تلقائياً من أول اسم في الاسم الكامل (القاعدة ٣) لين تعدّله الإدارة بيدها،
    /// وبعدها يبقى كما كُتب. يُحفظ كما هو في first_name (طلب المالك ٢٠٢٦-١٠-١٨: «زين العابدين»)
    @State private var firstName: String = ""
    @State private var firstNameEdited = false
    @State private var familyName: String = ""
    @State private var selectedGender: String = "male"
    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var selectedImage: UIImage? = nil
    @State private var phoneNumber: String = ""
    @State private var hasAttemptedSubmit = false
    @AppStorage("lastAuthDialingCode") private var lastAuthDialingCode: String = ""
    @State private var selectedPhoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var showingSuccess = false
    @State private var showingError = false

    @Environment(\.verticalSizeClass) private var vSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// الوضع الأفقي — عمودان
    private var isLandscape: Bool { vSizeClass == .compact }

    /// لون مجال «الشجرة والأعضاء»
    private let tint = DS.Color.composerProject

    // MARK: - التحقّق (نفس قواعد فورم التسجيل)

    private var trimmedFullName: String { fullName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedFamilyName: String { familyName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedFirstName: String { PersonName.clean(firstName) }
    /// الاسم الكامل يبدأ بالاسم الأول؟ (فاضي = ما نعرض التنبيه، التحقّق يمسكه)
    private var fullStartsWithFirst: Bool {
        trimmedFirstName.isEmpty || trimmedFullName.isEmpty
            || PersonName.startsWithFirstName(trimmedFullName, trimmedFirstName)
    }

    /// 2-50 حرف + على الأقل حرفان أبجديان
    private func isValidName(_ s: String) -> Bool {
        s.count >= 2 && s.count <= 50 && s.filter { $0.isLetter }.count >= 2
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if isLandscape {
                // الوضع الأفقي: الرأس والصورة بعمود، والحقول بعمود
                HStack(alignment: .top, spacing: DS.Spacing.lg) {
                    VStack(spacing: DS.Spacing.md) {
                        hero
                        photoSection
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: DS.Spacing.md) {
                        basicsSection
                        birthDateSection
                        phoneSection
                        submitButton
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            } else {
                VStack(spacing: DS.Spacing.md) {
                    hero
                    // الصورة الشخصية — في الأعلى مثل فورم التسجيل
                    photoSection
                    // الاسم الرباعي + اسم العائلة
                    basicsSection
                    birthDateSection
                    // رقم الهاتف (خاص بالإدارة — اختياري)
                    phoneSection
                    // زر الإرسال
                    submitButton
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        // الرأس الملوّن الموحّد (بدل شريط النظام وبطاقة الرأس)
        .dsSubPageHeader(L10n.t("تسجيل عضو جديد", "Register New Member"),
                         subtitle: L10n.t("أدخل بيانات العضو الجديد", "Enter the new member's details"))
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .dsAlert(L10n.t("تم التسجيل", "Registered"), isPresented: $showingSuccess, moment: .newMember) {
            Button(L10n.t("حسناً", "OK")) { dismiss() }
        } message: {
            Text(L10n.t("تمت إضافة العضو بنجاح.", "Member added successfully."))
        }
        .dsAlert(L10n.t("خطأ", "Error"), isPresented: $showingError) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("تعذر الإضافة. حاول مرة أخرى.", "Add failed. Try again."))
        }
        .onAppear {
            if !lastAuthDialingCode.isEmpty {
                selectedPhoneCountry = KuwaitPhone.countryForDialingCode(lastAuthDialingCode)
            }
        }
    }

    // MARK: - صفّ الأرقام — يتابع اكتمال النموذج (العنوان والوصف في الرأس الملوّن)

    private var hero: some View {
        let requiredDone = (isValidName(trimmedFullName) ? 1 : 0) + (isValidName(trimmedFamilyName) ? 1 : 0)
        return DSStatsRow([
            DSHeroStat(value: L10n.t("\(requiredDone) من 2", "\(requiredDone) of 2"),
                       label: L10n.t("الحقول المطلوبة", "Required fields"), icon: "checklist"),
            DSHeroStat(value: selectedImage == nil ? "—" : "✓",
                       label: L10n.t("الصورة", "Photo"), icon: "camera.fill"),
            DSHeroStat(value: phoneNumber.isEmpty ? "—" : "✓",
                       label: L10n.t("الرقم", "Phone"), icon: "phone.fill")
        ], tint: tint)
    }

    // MARK: - Photo Section — كاميرا على الصورة مباشرة (نفس فورم التسجيل)
    private var photoSection: some View {
        DSComposerSection(title: L10n.t("الصورة الشخصية", "Profile Photo"),
                          icon: "camera.fill",
                          tint: tint,
                          trailing: L10n.t("اختياري", "Optional"),
                          index: 1) {
            VStack(spacing: DS.Spacing.xs) {
                DSProfilePhotoPicker(
                    selectedImage: $selectedImage,
                    enableCrop: true,
                    cropShape: .circle,
                    title: L10n.t("الصورة الشخصية", "Profile Photo"),
                    trailing: nil,   // «اختياري» في عنوان القسم
                    compactEmptyState: true
                )

                Text(L10n.t(
                    "سوف تُستخدم كصورة في شجرة العائلة",
                    "Will be used as the member's photo in the family tree"
                ))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - البيانات الأساسية — الاسم الرباعي واسم العائلة (نفس فورم التسجيل)
    private var basicsSection: some View {
        DSComposerSection(title: L10n.t("البيانات الأساسية", "Basic Info"),
                          icon: "person.text.rectangle.fill",
                          tint: tint,
                          trailing: L10n.t("مطلوب", "Required"),
                          index: 2) {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSComposerField(
                    icon: "person.crop.circle",
                    label: L10n.t("الاسم الأول", "First name"),
                    placeholder: L10n.t("محمد", "Mohammad"),
                    text: $firstName,
                    tint: tint
                )
                .onChange(of: firstName) { _ in
                    if firstName.count > 50 { firstName = String(firstName.prefix(50)) }
                    // تعديل يدوي = يختلف عن التعبئة التلقائية؛ لو انمسح يرجع تلقائياً
                    let auto = PersonName.firstUnit(fullName)
                    firstNameEdited = !trimmedFirstName.isEmpty && trimmedFirstName != auto
                }

                Text(L10n.t("للأسماء المركبة مثل زين العابدين اكتبها كاملة هنا",
                            "For compound names like Zain Al-Abidin, write the whole name here"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.leading, DS.Spacing.sm)

                if hasAttemptedSubmit && trimmedFirstName.isEmpty {
                    validationError(L10n.t("الاسم الأول مطلوب", "First name is required"))
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSComposerField(
                    icon: "person.fill",
                    label: L10n.t("الاسم الرباعي (باللغة العربية)", "Full Name (in Arabic)"),
                    placeholder: L10n.t("محمد عبدالله علي أحمد", "Mohammad Abdullah Ali Ahmad"),
                    text: $fullName,
                    tint: tint
                )
                .onChange(of: fullName) { _ in
                    if fullName.count > 100 {
                        fullName = String(fullName.prefix(100))
                    }
                    if !firstNameEdited { firstName = PersonName.firstUnit(fullName) }
                }

                if hasAttemptedSubmit && trimmedFullName.isEmpty {
                    validationError(L10n.t("الاسم مطلوب", "Name is required"))
                } else if !fullStartsWithFirst {
                    validationError(L10n.t("الاسم الكامل لازم يبدأ بالاسم الأول",
                                           "The full name must start with the first name"))
                }
            }

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                DSComposerField(
                    icon: "person.2.fill",
                    label: L10n.t("اسم العائلة", "Family name"),
                    placeholder: L10n.t("[اسم العائلة]", "[Family name]"),
                    text: $familyName,
                    tint: DS.Color.accent
                )
                .onChange(of: familyName) { _ in
                    if familyName.count > 50 {
                        familyName = String(familyName.prefix(50))
                    }
                }

                if hasAttemptedSubmit && trimmedFamilyName.isEmpty {
                    validationError(L10n.t("اسم العائلة مطلوب", "Family name is required"))
                }
            }
        }
    }

    // MARK: - Birth Date Section — صف تاريخ يفتح مربّع التاريخ الموحّد بالمنتصف
    private var birthDateSection: some View {
        DSComposerSection(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                          icon: "calendar",
                          tint: tint,
                          index: 3) {
            Button {
                dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                    initial: birthDate,
                                    allowClear: false) { picked in
                    if let picked { birthDate = picked }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "gift.fill", tint: DS.Color.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("تاريخ الميلاد", "Birth Date"))
                            .dsFieldFont(.label)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(DSDateText.display(birthDate))
                            .dsFieldFont(DSBox.fieldValueSize, weight: .semibold)
                            .foregroundColor(DS.Color.fieldValue)
                    }
                    Spacer(minLength: 0)
                    DSStateIcon("pencil", tint: tint, size: DS.Icon.discSmall, mapsChrome: false)
                }
                .frame(minHeight: DSBox.fieldMinHeight)
                .dsRowBox()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("يفتح اختيار التاريخ", "Opens the date picker"))
        }
    }

    // MARK: - Phone Section — حقل موحّد مع كود الدولة على الجهة المقابلة
    private var phoneSection: some View {
        DSComposerSection(title: L10n.t("رقم الهاتف", "Phone Number"),
                          icon: "phone.fill",
                          tint: tint,
                          trailing: L10n.t("اختياري", "Optional"),
                          index: 4) {
            DSPhoneField(
                country: $selectedPhoneCountry,
                digits: $phoneNumber,
                placeholder: L10n.t("رقم الهاتف", "Phone Number"),
                compact: true,
                bordered: false
            )
            .dsFieldChrome()
        }
    }

    // MARK: - Submit Button
    private var submitButton: some View {
        let trimmedFull = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFamily = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
        // نفس Validation فورم التسجيل: 2-50 حرف + على الأقل حرفان أبجديان
        let fullLetterCount = trimmedFull.filter { $0.isLetter }.count
        let familyLetterCount = trimmedFamily.filter { $0.isLetter }.count
        let first = trimmedFirstName
        let isValid = trimmedFull.count >= 2 && trimmedFull.count <= 50 && fullLetterCount >= 2
                   && trimmedFamily.count >= 2 && trimmedFamily.count <= 50 && familyLetterCount >= 2
                   && !first.isEmpty && fullStartsWithFirst
        // يبدو معطّلاً حتى يكتمل — ويبقى قابلاً للضغط ليُظهر ما ينقص (كما كان)
        let looksEnabled = isValid && !memberVM.isLoading
        return Button {
            withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { hasAttemptedSubmit = true }
            guard isValid else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.locale = Locale(identifier: "en_US")

            let birthStr = formatter.string(from: birthDate)
            let storedPhone = KuwaitPhone.normalizedForStorage(
                country: selectedPhoneCountry,
                rawLocalDigits: phoneNumber
            )

            Task {
                let success = await memberVM.adminAddMember(
                    fullName: trimmedFull,
                    firstName: first,
                    birthDate: birthStr,
                    gender: selectedGender,
                    phoneNumber: storedPhone,
                    avatarImage: selectedImage
                )
                if success {
                    showingSuccess = true
                } else {
                    showingError = true
                }
            }
        } label: {
            // وجه الزرّ الواحد (`DSButtonFace`) — يبدو معطّلاً حتى يكتمل ويبقى قابلاً للضغط
            HStack(spacing: DSBox.buttonSpacing) {
                if memberVM.isLoading {
                    ProgressView().tint(DS.Color.textOnPrimary).scaleEffect(0.85)
                } else {
                    Image(systemName: "person.badge.plus")
                        .dsGlyph(DSButtonSize.regular.glyph)
                }
                Text(L10n.t("إضافة العضو", "Add Member"))
            }
            .modifier(DSButtonFace(enabled: looksEnabled))
        }
        .buttonStyle(DSPressStyle())
        .disabled(memberVM.isLoading)
        .padding(.top, DS.Spacing.xs)
        .dsStaggerIn(5)
    }

    // MARK: - Validation Error — نفس فورم التسجيل
    private func validationError(_ text: String) -> some View {
        HStack(spacing: DS.Spacing.xs) {
            Image(systemName: "exclamationmark.circle.fill")
                .dsGlyph(DS.Glyph.smCompact)
                .accessibilityHidden(true)
            Text(text)
                .dsFont(.caption)
        }
        .foregroundColor(DS.Color.error)
        .padding(.leading, DS.Spacing.sm)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
    }

}
