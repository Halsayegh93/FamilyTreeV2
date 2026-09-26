import SwiftUI

/// شاشة طلب تعديل الشجرة — تستقبل عضو + إجراء محددين مسبقاً.
/// تدعم: إضافة ابن / تعديل اسم / تعديل رقم / تسجيل وفاة / حذف.
struct TreeEditRequestView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isDetailsFocused: Bool
    @FocusState private var isPrimaryFieldFocused: Bool

    let member: FamilyMember
    let action: TreeEditAction

    @State private var primaryText: String = ""
    @State private var notes: String = ""
    @State private var deathDate: Date = Date()
    @State private var birthDate: Date = Date()
    @State private var selectedPhoto: UIImage? = nil
    @State private var isUploadingPhoto = false
    @State private var phoneCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var localPhoneDigits: String = ""
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var errorMessage: String? = nil
    @State private var showCountrySheet = false

    /// ارتفاع الشيت — يُقاس من المحتوى ليكون الشيت بحجم المحتوى عند الكتابة
    /// (نفس نمط AddChildSheet / EditChildSheet).
    @State private var sheetHeight: CGFloat = 360

    private var actionColor: Color {
        switch action {
        case .add: return DS.Color.success
        case .editName: return DS.Color.info
        case .editPhone: return DS.Color.primary
        case .editBirth: return DS.Color.warning
        case .deceased: return DS.Color.textTertiary
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return DS.Color.primary
        case .delete: return DS.Color.error
        case .other: return DS.Color.accent
        }
    }

    private var screenTitle: String {
        switch action {
        case .add: return L10n.t("طلب إضافة ابن", "Add Son Request")
        case .editName: return L10n.t("طلب تعديل اسم", "Edit Name Request")
        case .editPhone: return L10n.t("طلب تعديل رقم", "Edit Phone Request")
        case .editBirth: return L10n.t("طلب تعديل تاريخ الميلاد", "Edit Birth Date Request")
        case .deceased: return L10n.t("طلب تسجيل وفاة", "Mark Deceased Request")
        case .addDeathDate: return L10n.t("طلب إضافة تاريخ وفاة", "Add Death Date Request")
        case .addPhoto: return L10n.t("طلب إضافة صورة", "Add Photo Request")
        case .delete: return L10n.t("طلب حذف", "Delete Request")
        case .other: return L10n.t("طلب آخر", "Other Request")
        }
    }

    private var canSubmit: Bool {
        guard !adminRequestVM.isLoading, !isUploadingPhoto else { return false }
        switch action {
        case .add, .editName:
            return !primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .editPhone:
            return KuwaitPhone.normalizedForStorage(country: phoneCountry, rawLocalDigits: localPhoneDigits) != nil
        case .editBirth, .deceased, .addDeathDate:
            return true
        case .addPhoto:
            return selectedPhoto != nil
        case .delete, .other:
            return !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// لون الرأس — ألوان الأنواع الفاتحة تُعتَّم حتى يُقرأ النص الأبيض
    private var headerTint: Color {
        switch action {
        case .deceased, .addDeathDate: return DS.Color.textSecondary
        case .editPhone, .addPhoto, .editName, .other: return DS.Color.actionNavy
        // ألوان رؤوس غامقة تبقي النص الأبيض واضحاً بالوضع الداكن (ألوان الأقسام الفاتحة باهتة فيه)
        case .add: return DS.Color.composerProject
        case .editBirth: return DS.Color.composerLibrary
        case .delete: return DS.Color.error
        }
    }

    var body: some View {
        // نفس هيكل مربّعات الإضافة وحركتها (طلب المالك): رأس بلون نوع الطلب،
        // أقسام تدخل تباعاً، و«إرسال الطلب» / «إلغاء» أسفل المربّع
        DSComposer(
            title: screenTitle,
            subtitle: member.fullName,
            icon: action.iconName,
            tint: headerTint,
            actionTitle: L10n.t("إرسال الطلب", "Submit Request"),
            actionIcon: "paperplane.fill",
            canSubmit: canSubmit,
            isBusy: adminRequestVM.isLoading || isUploadingPhoto,
            note: L10n.t("يصل الطلب للإدارة لمراجعته", "Sent to the admins for review"),
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { submit() },
            onCancel: { dismiss() }
        ) {
            memberCard.dsStaggerIn(0)
            primaryFieldSection.dsStaggerIn(1)
            notesSection.dsStaggerIn(2)
        }
            .dsAlert(L10n.t("تم الإرسال", "Request Sent"), isPresented: $showSuccessAlert) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(L10n.t(
                    "تم إرسال طلبك للإدارة وسيتم مراجعته قريباً.",
                    "Your request has been sent to admin for review."
                ))
            }
            .dsAlert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(errorMessage ?? L10n.t(
                    "تعذر إرسال الطلب. حاول مرة أخرى.",
                    "Failed to send request. Please try again."
                ))
            }
            // اختيار الدولة — مربّع ثانٍ بمنتصف الشاشة فوق مربّع الطلب
            .dsCenterBox(isPresented: $showCountrySheet) {
                countryPickerSheet
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear { prefillFromMember() }
    }

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    /// ما يُرسل مع الطلب — يُقارن بما فُتح عليه المربّع (بعد التعبئة المسبقة)
    private struct Draft: Equatable {
        var primaryText: String
        var notes: String
        /// الدولة تُحسب مع الرقم فقط (رقم فارغ = لا رقم)
        var phone: String
        var birthDay: String
        var deathDay: String
    }

    /// نقطة البداية — تُلتقط مرة واحدة بعد prefillFromMember
    @State private var startDraft: Draft? = nil

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var currentDraft: Draft {
        Draft(
            primaryText: primaryText.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: localPhoneDigits.isEmpty ? "" : "\(phoneCountry.id)|\(localPhoneDigits)",
            birthDay: Self.dayFormatter.string(from: birthDate),
            deathDay: Self.dayFormatter.string(from: deathDate)
        )
    }

    /// نص أو تاريخ أو رقم أو صورة تختلف عمّا فُتح عليه المربّع — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        guard let startDraft else { return false }
        return selectedPhoto != nil || currentDraft != startDraft
    }

    // MARK: - Member Card

    private var memberCard: some View {
        HStack(spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(actionColor.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: action.iconName)
                    .font(DS.Font.plex(20, weight: .semibold))
                    .foregroundColor(actionColor)
            }
            .accessibilityHidden(true)   // زخرفة — نوع الطلب مكتوب بجانبها

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(action.arabicLabel, action.englishLabel))
                    .font(DS.Font.plex(12))
                    .fontWeight(.semibold)
                    .foregroundColor(actionColor)
                Text(member.displayFullName)
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(actionColor.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Primary Field

    @ViewBuilder
    private var primaryFieldSection: some View {
        switch action {
        case .add:
            textInputSection(
                label: L10n.t("اسم الابن الجديد", "New Son Name"),
                placeholder: L10n.t("اكتب اسم الابن...", "Enter son's name..."),
                icon: "person.badge.plus",
                text: $primaryText
            )
        case .editName:
            textInputSection(
                label: L10n.t("الاسم الجديد", "New Name"),
                placeholder: L10n.t("اكتب الاسم الجديد...", "Enter new name..."),
                icon: "pencil",
                text: $primaryText
            )
        case .editBirth:
            dateSection(
                title: L10n.t("تاريخ الميلاد الصحيح", "Correct Birth Date"),
                label: L10n.t("تاريخ الميلاد", "Birth Date"),
                date: $birthDate,
                iconColor: DS.Color.warning
            )
        case .editPhone:
            phoneInputSection
        case .deceased:
            deceasedDateSection
        case .addDeathDate:
            dateSection(
                title: L10n.t("تاريخ الوفاة", "Date of Death"),
                label: L10n.t("تاريخ الوفاة", "Date of Death"),
                date: $deathDate,
                iconColor: DS.Color.error
            )
        case .addPhoto:
            photoPickerSection
        case .delete, .other:
            EmptyView()
        }
    }

    /// قسم اختيار تاريخ عام — يُستخدم لتعديل الميلاد وإضافة تاريخ الوفاة.
    private func dateSection(title: String, label: String, date: Binding<Date>, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(title)
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            DSDateField(
                label: label,
                date: date,
                iconColor: iconColor,
                range: ...Date()
            )
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    /// قسم اختيار صورة — لطلب «إضافة صورة».
    private var photoPickerSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("الصورة المقترحة", "Suggested Photo"))
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            DSProfilePhotoPicker(
                selectedImage: $selectedPhoto,
                title: L10n.t("اضغط لاختيار صورة", "Tap to choose a photo"),
                trailing: nil,
                compactEmptyState: true
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func textInputSection(label: String, placeholder: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(label)
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(DS.Font.plex(14, weight: .medium))
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(width: 24)

                TextField(placeholder, text: text)
                    .font(DS.Font.plex(15))
                    .foregroundColor(DS.Color.textPrimary)
                    .focused($isPrimaryFieldFocused)

                if !text.wrappedValue.isEmpty {
                    Button { text.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(DS.Font.plex(14, weight: .medium))
                            .foregroundColor(DS.Color.textTertiary)
                            // مساحة ضغط ٤٤ نقطة (حد أبل): العرض من مساحة الكتابة والأيقونة
                            // في مكانها على الطرف، والطول داخل هامش الصندوق — فلا يتغيّر
                            // ارتفاع الحقل ولا شكله
                            .frame(width: 44, alignment: .trailing)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                            .padding(.vertical, -14)
                    }
                    .accessibilityLabel(L10n.t("مسح النص", "Clear text"))
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isPrimaryFieldFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isPrimaryFieldFocused ? 1.5 : 1
                    )
            )
        }
    }

    private var phoneInputSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("الرقم الجديد", "New Phone Number"))
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            DSPhoneField(
                country: $phoneCountry,
                digits: $localPhoneDigits,
                placeholder: L10n.t("رقم الهاتف", "Phone number")
            )
        }
    }

    /// اختيار دولة الرقم — مربّع بمنتصف الشاشة بتصميم المربّعات الموحّد: الدول صفوفاً
    /// والمختارة بعلامة ✓، والضغط على دولة يختارها ويغلق المربّع (كالسابق)
    private var countryPickerSheet: some View {
        DSComposer(
            title: L10n.t("اختر الدولة", "Select Country"),
            subtitle: L10n.t("رمز الدولة للرقم الجديد", "Country code for the new number"),
            icon: "globe",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إلغاء", "Cancel"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { showCountrySheet = false }
        ) {
            DSComposerSection(title: L10n.t("الدول", "Countries"), icon: "globe",
                              tint: DS.Color.primary, index: 0) {
                // صفوف عادية لا كسولة — القائمة قصيرة وتُقاس كاملةً فلا يُقصّ آخرها
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(KuwaitPhone.supportedCountries) { country in
                        countryRow(country)
                    }
                }
            }
        }
    }

    /// صف دولة: العلم بمربّع أيقونة الحقل + الاسم والرمز، والمختارة بعلامة ✓ وإطار
    private func countryRow(_ country: KuwaitPhone.Country) -> some View {
        let isSelected = phoneCountry == country
        return Button {
            phoneCountry = country
            showCountrySheet = false
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Text(country.flag)
                    .font(DS.Font.scaled(20))
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.08)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t(country.nameArabic, country.isoCode))
                        .font(DS.Font.plex(14.5, weight: .bold))
                        .foregroundColor(DS.Color.fieldLabel)
                    // علامة اتجاه (LRM) حتى يظهر «+965» لا «965+» في العربي
                    Text("\u{200E}" + country.dialingCode)
                        .font(DS.Font.plex(12))
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(DS.Color.primary)
                        .accessibilityHidden(true)   // الاختيار يُقرأ من حالة الزر
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var deceasedDateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(L10n.t("تاريخ الوفاة", "Date of Death"))
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            DSDateField(
                label: L10n.t("تاريخ الوفاة", "Date of Death"),
                date: $deathDate,
                iconColor: DS.Color.error,
                range: ...Date()
            )
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
            )
        }
    }

    // MARK: - Notes / Reason Section

    private var notesSection: some View {
        // مربّع الملاحظات صغير (طلب المالك) — يكبر بالكتابة لا أكثر
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(notesLabel)
                .font(DS.Font.plex(13, weight: .bold))
                .foregroundColor(DS.Color.textPrimary)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $notes)
                    .frame(minHeight: notesRequired ? 56 : 38)
                    .focused($isDetailsFocused)
                    .scrollContentBackground(.hidden)
                    .font(DS.Font.plex(14))
                    // القارئ الصوتي: مربّع الكتابة بلا اسم — العنوان اسمه والتلميح وصفه
                    .accessibilityLabel(notesLabel)
                    .accessibilityHint(notesPlaceholder)

                if notes.isEmpty {
                    Text(notesPlaceholder)
                        .font(DS.Font.plex(14))
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.top, DS.Spacing.sm)
                        .padding(.leading, DS.Spacing.xs)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)   // يُقرأ تلميحاً لمربّع الكتابة
                }
            }
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xs)
            .background(DS.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(
                        isDetailsFocused ? DS.Color.primary.opacity(0.4) : DS.Color.textTertiary.opacity(0.15),
                        lineWidth: isDetailsFocused ? 1.5 : 1
                    )
            )
        }
    }

    /// الملاحظات مطلوبة في الحذف و«أخرى» — تأخذ ارتفاعاً أكبر قليلاً
    private var notesRequired: Bool { action == .delete || action == .other }

    private var notesLabel: String {
        switch action {
        case .delete:
            return L10n.t("سبب الحذف (مطلوب)", "Removal Reason (required)")
        case .other:
            return L10n.t("تفاصيل الطلب (مطلوب)", "Request Details (required)")
        default:
            return L10n.t("ملاحظات إضافية (اختياري)", "Additional Notes (optional)")
        }
    }

    private var notesPlaceholder: String {
        switch action {
        case .delete:
            return L10n.t("اكتب سبب طلب الحذف...", "Write the removal reason...")
        case .other:
            return L10n.t("اكتب طلبك أو ملاحظتك للإدارة...", "Write your request to admin...")
        default:
            return L10n.t("أي ملاحظات إضافية...", "Any additional notes...")
        }
    }

    // MARK: - Submit

    /// «إرسال الطلب» و«إلغاء» جنب بعض، والإلغاء في الجهة اليسرى (طلب المالك)
    private var submitButton: some View {
        HStack(spacing: DS.Spacing.sm) {
            Button { submit() } label: {
                Group {
                    if adminRequestVM.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Label(L10n.t("إرسال الطلب", "Submit Request"), systemImage: "paperplane.fill")
                            .font(DS.Font.plex(14, weight: .bold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(canSubmit ? actionColor : actionColor.opacity(0.4)))
            }
            .disabled(!canSubmit)

            Button { dismiss() } label: {
                Text(L10n.t("إلغاء", "Cancel"))
                    .font(DS.Font.plex(14, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.mutedBackground.opacity(0.8)))
            }
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Helpers

    private func prefillFromMember() {
        switch action {
        case .editName:
            primaryText = member.fullName
        case .editPhone:
            if let phone = member.phoneNumber, !phone.isEmpty {
                let detected = KuwaitPhone.detectCountryAndLocal(phone)
                phoneCountry = detected.country
                localPhoneDigits = detected.localDigits
            }
        default:
            break
        }
        // نقطة البداية لـ«تغييرات لم تُحفظ» — المعبّأ مسبقاً ليس تغييراً (مرة واحدة فقط)
        if startDraft == nil { startDraft = currentDraft }
    }

    private func submit() {
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload: TreeEditPayload

        switch action {
        case .add:
            payload = TreeEditPayload.make(
                action: .add,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                parentMemberId: member.id.uuidString,
                parentMemberName: member.fullName,
                newMemberName: primaryText.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .editName:
            payload = TreeEditPayload.make(
                action: .editName,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newName: primaryText.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .editPhone:
            guard let normalized = KuwaitPhone.normalizedForStorage(country: phoneCountry, rawLocalDigits: localPhoneDigits) else {
                errorMessage = L10n.t("رقم الهاتف غير صالح", "Invalid phone number")
                showErrorAlert = true
                return
            }
            payload = TreeEditPayload.make(
                action: .editPhone,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newPhone: normalized,
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .deceased:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            payload = TreeEditPayload.make(
                action: .deceased,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                deathDate: formatter.string(from: deathDate),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .delete:
            payload = TreeEditPayload.make(
                action: .delete,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                reason: cleanNotes
            )

        case .editBirth:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            payload = TreeEditPayload.make(
                action: .editBirth,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newBirthDate: formatter.string(from: birthDate),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .addDeathDate:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            payload = TreeEditPayload.make(
                action: .addDeathDate,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                deathDate: formatter.string(from: deathDate),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .addPhoto:
            // الرفع غير متزامن — نُنفّذه في Task مستقل ثم نرسل الطلب.
            guard let image = selectedPhoto else { return }
            isUploadingPhoto = true
            Task {
                let url = await adminRequestVM.uploadPhotoSuggestion(image)
                isUploadingPhoto = false
                guard let url = url else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = L10n.t("تعذر رفع الصورة", "Photo upload failed")
                    showErrorAlert = true
                    return
                }
                let photoPayload = TreeEditPayload.make(
                    action: .addPhoto,
                    targetMemberId: member.id.uuidString,
                    targetMemberName: member.fullName,
                    newPhotoUrl: url,
                    notes: cleanNotes.isEmpty ? nil : cleanNotes
                )
                let sent = await adminRequestVM.submitTreeEditRequest(payload: photoPayload)
                if sent {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showSuccessAlert = true
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    showErrorAlert = true
                }
            }
            return

        case .other:
            payload = TreeEditPayload.make(
                action: .other,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                notes: cleanNotes
            )
        }

        Task {
            let sent = await adminRequestVM.submitTreeEditRequest(payload: payload)
            if sent {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                showSuccessAlert = true
            } else {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showErrorAlert = true
            }
        }
    }
}
