import SwiftUI

/// مربّع صغير لتعديل حقل واحد من «البيانات الشخصية» (طلب المالك ٢٠٢٦-١١-١٠): الضغط على الخانة يفتح مربّعها هي —
/// الحقل وحده، وتحته «إظهار للأعضاء» إن كان له خيار خصوصية، ثم «حفظ» / «إلغاء». نفس رأس المربّعات (`DSComposer`)
/// وحارس «تجاهل التعديلات؟». مربّع «تعديل البيانات» الكامل (القلم بجانب الاسم) كما هو.
///
/// الحفظ بالنداءات الموجودة نفسها:
/// - الميلاد والحالة الاجتماعية: `updateMemberData` ضمن حدّ التعديلات الذاتية (`ProfileEditCooldown`)،
///   وبعد الحدّ طلب للإدارة (`submitTreeEditRequest`) — كمربّع التعديل الكامل.
/// - الرقم الجديد: طلب للإدارة (`requestPhoneNumberChange`).
/// - «إظهار للأعضاء»: نداءات الخصوصية (`updatePhoneHidden` / `updateBirthDateHidden`) كمربّع الخصوصية السابق.
struct ProfileFieldEditBox: View {
    let field: ProfileEditField
    let member: FamilyMember

    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var adminRequestVM: AdminRequestViewModel
    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) private var dismiss

    private let cooldown = ProfileEditCooldown.shared

    @State private var loaded = false
    @State private var birthDate = Date()
    @State private var isMarried = false
    @State private var country: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var digits = ""
    @State private var originalDigits = ""
    @State private var phoneHidden = false
    @State private var birthHidden = false
    @State private var isSaving = false
    @State private var failed = false
    @State private var resultMessage: String?

    var body: some View {
        DSComposer(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: hasChanges && isValid && !isSaving && network.isConnected,
            isBusy: isSaving,
            note: network.isConnected ? note : L10n.t("لا يمكن الحفظ بدون اتصال", "Can't save while offline"),
            hasUnsavedChanges: hasChanges,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            // فاصل الأقسام الموحّد في المربّعات (`DSBox.sectionSpacing`)
            VStack(spacing: DSBox.sectionSpacing) {
                switch field {
                case .birth:
                    DatePicker("", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .environment(\.locale, LanguageManager.shared.locale)
                        .environment(\.calendar, Calendar(identifier: .gregorian))
                        .accessibilityLabel(L10n.t("تاريخ الميلاد", "Birth date"))
                    visibilitySection(hidden: $birthHidden, what: L10n.t("تاريخ الميلاد", "The birth date"))
                case .phone:
                    // صفّ الحقل الموحّد (رمز + عنوان + القيمة في صندوق الصفوف)، والمؤشّر فيه
                    DSPhoneFieldRow(country: $country, digits: $digits, autoFocus: true)
                    if digitsChanged {
                        Text(L10n.t("الرقم الجديد يُرسل إلى الإدارة للمراجعة.",
                                    "The new number is sent to the admins for review."))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    visibilitySection(hidden: $phoneHidden, what: L10n.t("رقم الهاتف", "The phone number"))
                case .marital:
                    DSMenuTile(icon: "heart.fill", label: L10n.t("الحالة الاجتماعية", "Marital status"), options: [
                        DSChoiceOption(id: false, title: member.isWomanAccount ? L10n.t("عزباء", "Single") : L10n.t("أعزب", "Single"),
                                       icon: "person.fill"),
                        DSChoiceOption(id: true, title: member.isWomanAccount ? L10n.t("متزوجة", "Married") : L10n.t("متزوج", "Married"),
                                       icon: "heart.fill")
                    ], selection: $isMarried)
                }
                if failed {
                    DSNoteCard(L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save, please try again."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
        .onAppear(perform: load)
        .dsAlert(L10n.t("تم", "Done"),
                 isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } }),
                 moment: .success) {
            Button(L10n.t("حسناً", "OK")) { dismiss() }
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: - العناوين

    private var title: String {
        switch field {
        case .birth: return L10n.t("تاريخ الميلاد", "Birth date")
        case .phone: return L10n.t("رقم الهاتف", "Phone number")
        case .marital: return L10n.t("الحالة الاجتماعية", "Marital status")
        }
    }

    private var subtitle: String {
        switch field {
        case .birth, .phone: return L10n.t("القيمة وظهورها للأعضاء", "Value and visibility to members")
        case .marital: return L10n.t("كما تظهر لأفراد العائلة", "As the family sees it")
        }
    }

    private var icon: String {
        switch field {
        case .birth: return "calendar"
        case .phone: return "phone.fill"
        case .marital: return "heart.fill"
        }
    }

    /// تنبيه حدّ التعديلات: بعد الحدّ يُرسل التغيير للإدارة
    private var note: String? {
        switch field {
        case .birth where !cooldown.canEdit(.birthDate):
            return L10n.t("بلغت حدّ التعديلات — يُرسل التاريخ الجديد إلى الإدارة.", "Edit limit reached — the new date goes to the admins.")
        case .marital where !cooldown.canEdit(.isMarried):
            return L10n.t("بلغت حدّ التعديلات — يُرسل التغيير إلى الإدارة.", "Edit limit reached — the change goes to the admins.")
        default:
            return nil
        }
    }

    // MARK: - عناصر الحقل

    /// قسم منفصل أسفل المربّع: «من يرى هذه المعلومة؟» — القاعدة الحقيقية: المخفي لا يراه الأعضاء،
    /// ويبقى ظاهراً لصاحبه وللإدارة (`dsVisiblePhone` / إخفاء الميلاد في تفاصيل العضو)
    private func visibilitySection(hidden: Binding<Bool>, what: String) -> some View {
        // قسم «الخصوصية» (عنوانه وقفله من `DSVisibilityPicker`) — كتلة واحدة يفصلها خطّ عن محرّر الحقل فوقها
        DSComposerSection(title: L10n.t("الخصوصية", "Privacy"), icon: "lock.fill",
                          tint: DS.Color.primary, index: 1) {
            DSVisibilityPicker(
                hidden: hidden,
                shownLine: L10n.t("يظهر \(what) لأعضاء العائلة.", "\(what) is shown to family members."),
                hiddenLine: L10n.t("لا يظهر \(what) لأعضاء العائلة، ويبقى ظاهراً لك وللإدارة.",
                                   "\(what) is hidden from family members; you and the admins still see it."),
                rowTitle: what)
        }
    }

    private func maritalOption(single: Bool) -> some View {
        let female = member.isWomanAccount
        let title = single ? (female ? L10n.t("عزباء", "Single") : L10n.t("أعزب", "Single"))
                           : (female ? L10n.t("متزوجة", "Married") : L10n.t("متزوج", "Married"))
        let selected = single ? !isMarried : isMarried
        return DSChipButton(title, tint: DS.Color.primary, isSelected: selected, fillsWidth: true) {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.quick) { isMarried = !single }
        }
    }

    // MARK: - الحالة

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let d = DateHelper.parse(member.birthDate) { birthDate = d }
        isMarried = member.isMarried ?? false
        let detected = KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
        country = detected.country
        digits = detected.localDigits
        originalDigits = detected.localDigits
        phoneHidden = member.isPhoneHidden ?? false
        birthHidden = member.isBirthDateHidden ?? false
    }

    private var birthChanged: Bool {
        guard let old = DateHelper.parse(member.birthDate) else { return true }
        return DateHelper.format(old) != DateHelper.format(birthDate)
    }
    private var digitsChanged: Bool { digits != originalDigits }
    private var newPhone: String? { KuwaitPhone.normalizedForStorage(country: country, rawLocalDigits: digits) }

    private var hasChanges: Bool {
        switch field {
        case .birth: return birthChanged || birthHidden != (member.isBirthDateHidden ?? false)
        case .phone: return digitsChanged || phoneHidden != (member.isPhoneHidden ?? false)
        case .marital: return isMarried != (member.isMarried ?? false)
        }
    }

    private var isValid: Bool { field != .phone || !digitsChanged || newPhone != nil }

    // MARK: - الحفظ (النداءات الموجودة)

    private func save() {
        guard !isSaving, NetworkMonitor.shared.requireOnline() else { return }
        isSaving = true
        failed = false
        Task {
            var saved: [String] = []
            var sent: [String] = []
            var ok = true
            switch field {
            case .birth:
                if birthHidden != (member.isBirthDateHidden ?? false) {
                    if await memberVM.updateBirthDateHidden(birthHidden) {
                        saved.append(L10n.t("ظهور تاريخ الميلاد", "Birth date visibility"))
                    } else { ok = false }
                }
                if birthChanged {
                    if cooldown.canEdit(.birthDate) {
                        if await saveMemberData(birthDate: birthDate, isMarried: member.isMarried ?? false) {
                            cooldown.recordEdit(.birthDate)
                            saved.append(L10n.t("تاريخ الميلاد", "Birth date"))
                        } else { ok = false }
                    } else {
                        let done = await adminRequestVM.submitTreeEditRequest(payload: .make(
                            action: .editBirth,
                            targetMemberId: member.id.uuidString,
                            targetMemberName: member.fullName,
                            newBirthDate: DateHelper.format(birthDate),
                            notes: L10n.t("تعديل بعد تجاوز حد التعديلات", "Edit after reaching the edit limit")))
                        if done { sent.append(L10n.t("تاريخ الميلاد", "Birth date")) } else { ok = false }
                    }
                }
            case .phone:
                if phoneHidden != (member.isPhoneHidden ?? false) {
                    if await memberVM.updatePhoneHidden(phoneHidden) {
                        saved.append(L10n.t("ظهور رقم الهاتف", "Phone visibility"))
                    } else { ok = false }
                }
                if digitsChanged, let phone = newPhone {
                    if await adminRequestVM.requestPhoneNumberChange(memberId: member.id, newPhoneNumber: phone) {
                        sent.append(L10n.t("رقم الهاتف", "Phone number"))
                    } else { ok = false }
                }
            case .marital:
                if cooldown.canEdit(.isMarried) {
                    if await saveMemberData(birthDate: DateHelper.parse(member.birthDate), isMarried: isMarried) {
                        cooldown.recordEdit(.isMarried)
                        saved.append(L10n.t("الحالة الاجتماعية", "Marital status"))
                    } else { ok = false }
                } else {
                    let done = await adminRequestVM.submitTreeEditRequest(payload: .make(
                        action: .other,
                        targetMemberId: member.id.uuidString,
                        targetMemberName: member.fullName,
                        newName: isMarried ? "true" : "false",
                        reason: "profile_marital",
                        notes: L10n.t("طلب تغيير الحالة الاجتماعية إلى: \(isMarried ? "متزوج" : "غير متزوج")",
                                      "Marital status change to: \(isMarried ? "Married" : "Single")")))
                    if done { sent.append(L10n.t("الحالة الاجتماعية", "Marital status")) } else { ok = false }
                }
            }
            isSaving = false
            guard ok else { failed = true; return }
            let sep = L10n.t("، ", ", ")
            var lines: [String] = []
            if !saved.isEmpty { lines.append(L10n.t("تغيّر: ", "Changed: ") + saved.joined(separator: sep)) }
            if !sent.isEmpty {
                lines.append(L10n.t("أُرسل إلى الإدارة: ", "Sent to admins: ") + sent.joined(separator: sep)
                             + L10n.t("\nيتغيّر بعد الموافقة.", "\nApplies after approval."))
            }
            if lines.isEmpty { dismiss() } else { resultMessage = lines.joined(separator: "\n") }
        }
    }

    /// نفس نداء مربّع التعديل الكامل — بقية الحقول بقيمها المحفوظة كما هي
    private func saveMemberData(birthDate: Date?, isMarried: Bool) async -> Bool {
        await memberVM.updateMemberData(
            memberId: member.id,
            fullName: member.fullName,
            phoneNumber: member.phoneNumber ?? "",
            birthDate: birthDate,
            isMarried: isMarried,
            isDeceased: member.isDeceased ?? false,
            deathDate: member.isDeceased ?? false ? DateHelper.parse(member.deathDate) : nil,
            isPhoneHidden: member.isPhoneHidden ?? false
        )
    }
}


/// مربّع «الظهور في الشجرة» لفرد من «الأسرة» (طلب المالك ٢٠٢٦-١١-١٠ «نفس التصميم عند أسرتي») — بنفس مربّع الحقل
/// الواحد: رأس كحلي، قسم «الخصوصية» (`DSVisibilityPicker`)، «حفظ» / «إلغاء» وحارس التعديلات. يُستعمل للزوج
/// («ظهور الزوج») والأبناء وللمرأة نفسها («الظهور في الشجرة») — الحفظ بدالة المستعمل (النداءات الموجودة نفسها).
struct FamilyVisibilityBox: View {
    let title: String
    let subtitle: String
    let icon: String
    let initiallyHidden: Bool
    /// صاحب الصفّ امرأة (المرأة نفسها) — «ظاهرة / مخفية»
    var feminine: Bool = false
    let shownLine: String
    let hiddenLine: String
    /// يرجع true عند النجاح (المربّع يُغلق)، false يبقيه مفتوحاً برسالة الخطأ
    let onSave: (_ hidden: Bool) async -> Bool

    @ObservedObject private var network = NetworkMonitor.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hidden = false
    @State private var loaded = false
    @State private var isSaving = false
    @State private var failed = false

    var body: some View {
        DSComposer(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            actionIcon: "checkmark",
            canSubmit: hidden != initiallyHidden && !isSaving && network.isConnected,
            isBusy: isSaving,
            note: network.isConnected ? nil : L10n.t("لا يمكن الحفظ بدون اتصال", "Can't save while offline"),
            hasUnsavedChanges: hidden != initiallyHidden,
            onSubmit: save,
            onCancel: { dismiss() }
        ) {
            VStack(spacing: DSBox.sectionSpacing) {
                DSComposerSection(title: L10n.t("الخصوصية", "Privacy"), icon: "lock.fill",
                                  tint: DS.Color.primary, index: 0) {
                    DSVisibilityPicker(hidden: $hidden, shownLine: shownLine, hiddenLine: hiddenLine,
                                       rowTitle: L10n.t("الظهور في شجرة النساء", "Shown in the women's tree"), feminine: feminine)
                }
                if failed {
                    DSNoteCard(L10n.t("تعذّر الحفظ، يرجى المحاولة مرة أخرى.", "Couldn't save, please try again."),
                               icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
                }
            }
        }
        .onAppear { if !loaded { loaded = true; hidden = initiallyHidden } }
    }

    private func save() {
        guard !isSaving, NetworkMonitor.shared.requireOnline() else { return }
        isSaving = true; failed = false
        Task {
            let ok = await onSave(hidden)
            isSaving = false
            if ok { dismiss() } else { failed = true }
        }
    }
}
