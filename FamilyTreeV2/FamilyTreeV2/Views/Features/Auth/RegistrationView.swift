import SwiftUI

struct RegistrationView: View {
    @EnvironmentObject var authVM: AuthViewModel

    @State private var fullName: String = ""
    @State private var familyName: String = ""
    /// مسافة علوية إضافية — تستخدمها المعاينة حتى لا يغطّي شريطها المحتوى
    var topInset: CGFloat = 0

    @StateObject private var familyNamesVM = FamilyNamesViewModel()
    /// انتهى أول جلب لقائمة العوائل؟ — تلميح «القائمة فارغة» لا يومض قبل الجلب
    @State private var familiesFetched = false
    /// إدخال يدوي لاسم العائلة — يُستخدم إن تعذّر جلب القائمة أو لم تكن مدرجة
    @State private var showManualFamily = false
    @State private var manualFamilyText = ""

    @State private var birthDate: Date = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    /// اختار تاريخه فعلاً؟ — وإلا لا يُحفظ تاريخ «قبل ٢٠ سنة» الافتراضي كأنه تاريخ ميلاده (حدث ٢٠٢٦-١٠-٠٥)
    @State private var birthDateChosen = false
    /// الجنس مطلوب بلا اختيار مسبق (الدفعة ١٢ — كان «ذكر» ثابتاً فيُسجَّل كل منضم ذكراً): «male» أو «female»
    @State private var selectedGender: String = ""
    /// دخول النساء (٢٠٢٦-١٠-٢٤): الأنثى تختار أباها من شجرة الرجال — يُحمل في طلب الانضمام لا في ملفها
    /// (مكانها شجرة النساء تحت أبيها، تربطها الإدارة)
    @State private var selectedFather: FamilyMember? = nil
    @State private var showFatherPicker = false
    @State private var fatherSearch = ""
    @State private var fatherResults: [FamilyMember] = []
    @State private var fatherSearching = false
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
                        AnyView(photoSection)
                            .scaleEffect(headerScale)
                            .opacity(headerOpacity)

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
                                AnyView(familyNameSection)
                                AnyView(birthDateSection)
                                AnyView(genderSection)
                                if selectedGender == "female" {
                                    AnyView(fatherSection)
                                }
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
        .dsAlert(L10n.t("اسم العائلة", "Family name"), isPresented: $showManualFamily) {
            TextField(L10n.t("مثال: الصايغ", "e.g. Al-Sayegh"), text: $manualFamilyText)
                .dsAlertField()
            Button(L10n.t("حفظ", "Save")) {
                let t = manualFamilyText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { familyName = t }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        }
        .dsCenterBox(isPresented: $showFatherPicker) {
            fatherPickerBox
        }
        .task {
            await familyNamesVM.fetch()
            familiesFetched = true
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
        DSSubPageHeader(title: L10n.t("إكمال البيانات", "Complete Profile"),
                        subtitle: L10n.t("خطوة واحدة وتنضم لشجرة العائلة",
                                         "One step to join the family tree"),
                        icon: "person.badge.plus",
                        nav: .none) {
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
                label: L10n.t("الاسم الرباعي", "Full Name (4 parts)") + " " + L10n.t("(باللغة العربية)", "(in Arabic)"),
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

            if hasAttemptedSubmit && fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("الاسم مطلوب", "Name is required"))
            }
        }
    }

    // MARK: - Family Name
    /// اختيار العائلة — بنفس هيئة حقل «الاسم الرباعي» حرفياً (أيقونة + عنوان
    /// + قيمة) فتبدو كل الحقول قطعة واحدة.
    private var familyNameSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Menu {
                ForEach(familyNamesVM.activeNames, id: \.self) { option in
                    Button {
                        familyName = option
                    } label: {
                        if familyName == option {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
                // القائمة لا تُترك فارغة: إعادة محاولة + كتابة يدوية
                if familyNamesVM.activeNames.isEmpty {
                    Button {
                        Task { await familyNamesVM.fetch(force: true) }
                    } label: {
                        Label(L10n.t("إعادة تحميل القائمة", "Reload list"),
                              systemImage: "arrow.clockwise")
                    }
                }
                Divider()
                Button {
                    manualFamilyText = familyName
                    showManualFamily = true
                } label: {
                    Label(L10n.t("كتابة اسم العائلة يدوياً", "Type family name"),
                          systemImage: "pencil")
                }
            } label: {
                // نفس صفّ حقول المربّعات: قرص مجسّم + عنوان + قيمة
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "person.2.fill", tint: DS.Color.accent)

                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xxs) {
                            Text(L10n.t("العائلة", "Family"))
                                .foregroundColor(DS.Color.fieldLabel)
                            Text("*").foregroundColor(DS.Color.error)
                        }
                        .dsFieldFont(.label)

                        Text(familyName.isEmpty
                             ? L10n.t("اختر عائلتك", "Choose your family")
                             : familyName)
                            .dsFieldFont(.fieldValue)
                            .foregroundColor(familyName.isEmpty
                                             ? DS.Color.textTertiary
                                             : DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if familyNamesVM.isLoading {
                        ProgressView().scaleEffect(0.7)   // دوّارة صغيرة داخل الحقل
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .dsGlyph(DS.Glyph.sm, weight: .semibold)
                            .foregroundColor(DS.Color.textTertiary)
                    }
                }
                .frame(minHeight: DSBox.fieldMinHeight)
                .dsRowBox()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasAttemptedSubmit && familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                validationError(L10n.t("اختيار العائلة مطلوب", "Choosing a family is required"))
            }

            // ملاحظة الربط — الاسم الأخير هو العائلة المختارة (كانت تحت الجنس المخفي — مكانها تحت العائلة)
            Text(familyName.isEmpty
                 ? L10n.t("العائلة التي تختارها تُضاف تلقائياً كاسم أخير",
                          "The family you choose is added automatically as your last name")
                 : L10n.t("اسمك الأخير سيكون: \(familyName)",
                          "Your last name will be: \(familyName)"))
            .dsFont(.footnote)
            .foregroundColor(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

            // فقط إن جاءت القائمة فارغة فعلاً (بعد انتهاء الجلب بلا خطأ)
            if familiesFetched
                && familyNamesVM.errorMessage == nil
                && !familyNamesVM.isLoading
                && familyNamesVM.activeNames.isEmpty {
                Text(L10n.t("القائمة فارغة — تظهر العوائل بعد تسجيل الدخول",
                            "Empty list — families load after sign-in"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let err = familyNamesVM.errorMessage {
                Text(L10n.t("تعذّر جلب قائمة العوائل: \(err)",
                            "Could not load families: \(err)"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Birth Date — صفّ تاريخ يفتح مربّع التاريخ الموحّد بالمنتصف (نفس «تسجيل عضو جديد»)
    private var birthDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
        Button {
            dsPresentDatePicker(title: L10n.t("تاريخ الميلاد", "Birth Date"),
                                initial: birthDate, allowClear: false) { picked in
                guard let picked else { return }
                birthDate = picked
                birthDateChosen = true
            }
        } label: {
            DSRow(icon: "gift.fill", tint: DS.Color.warning,
                  title: L10n.t("تاريخ الميلاد", "Birth Date") + " *",
                  subtitle: birthDateChosen ? DSDateText.display(birthDate) : L10n.t("بدون تاريخ", "No date")) {
                DSStateIcon("pencil", tint: DS.Color.primary, size: DS.Icon.row)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح اختيار التاريخ", "Opens the date picker"))

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
        // الأب لغير الأنثى لا يُحمل
        .onChange(of: selectedGender) { g in
            if g != "female" { selectedFather = nil }
        }
    }

    // MARK: - Father (الأنثى) — صفّ يفتح منتقي الأعضاء الموحّد ببحث السيرفر
    private var fatherSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button {
                if fatherSearch.isEmpty { fatherSearch = suggestedFatherQuery }
                showFatherPicker = true
            } label: {
                DSRow(icon: "figure.and.child.holdinghands", tint: DS.Color.palm,
                      title: L10n.t("الأب", "Father"),
                      subtitle: selectedFather?.displayFullName ?? L10n.t("اختاري أباك من الشجرة", "Pick your father from the tree")) {
                    DSStateIcon("magnifyingglass", tint: DS.Color.primary, size: DS.Icon.row)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.t("يفتح البحث عن الأب", "Opens the father search"))

            Text(L10n.t("تُربطين بشجرة النساء تحت أبيك — يسهّل على الإدارة قبول طلبك",
                        "You'll be placed in the women's tree under your father — it helps the admins approve you"))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// اسم الأب المقترح للبحث: الاسم المكتوب بلا الاسم الأول
    private var suggestedFatherQuery: String {
        let parts = fullName.split(whereSeparator: \.isWhitespace).map(String.init)
        return parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
    }

    private var fatherPickerBox: some View {
        DSMemberPickerBox(
            title: L10n.t("اختيار الأب", "Choose father"),
            subtitle: L10n.t("من شجرة العائلة", "From the family tree"),
            icon: "figure.and.child.holdinghands",
            candidates: fatherResults,
            search: $fatherSearch,
            isLoading: fatherSearching,
            requiresSpecificQuery: true,
            searchLabel: L10n.t("اسم الأب", "Father's name"),
            searchPlaceholder: L10n.t("اسم الأب الثلاثي", "Father's three-part name"),
            hintTitle: L10n.t("اكتبي اسم أبيك الثلاثي", "Type your father's three-part name"),
            hintMessage: L10n.t("بدون اسم العائلة", "Without the family name"),
            noMatchTitle: L10n.t("لم نجد هذا الاسم", "Name not found"),
            emptyMessage: L10n.t("جرّبي الاسم بدون اسم العائلة، أو اتركيه وتربطك الإدارة",
                                 "Try without the family name, or skip it and the admins will place you"),
            selectedId: selectedFather?.id,
            onPick: { m in
                selectedFather = m
                showFatherPicker = false
            },
            onCancel: { showFatherPicker = false }
        )
        // بحث السيرفر بعد توقّف الكتابة قليلاً
        .task(id: fatherSearch) {
            let q = fatherSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard q.split(whereSeparator: \.isWhitespace).count >= 2 else {
                fatherResults = []
                fatherSearching = false
                return
            }
            fatherSearching = true
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let found = await authVM.searchFatherCandidates(q)
            guard !Task.isCancelled else { return }
            fatherResults = found
            fatherSearching = false
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
                            fatherId: selectedGender == "female" ? selectedFather?.id : nil,
                            fatherName: selectedGender == "female" ? selectedFather?.fullName : nil,
                            avatarImage: selectedImage
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
