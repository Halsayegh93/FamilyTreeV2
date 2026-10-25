import SwiftUI

/// شاشة طلب تعديل الشجرة — تستقبل عضو + إجراء محددين مسبقاً.
/// تدعم: إضافة ابن (أو أكثر) / تعديل اسم / تعديل رقم / تسجيل وفاة / حذف.
/// «ابن» هنا أبناء ذكور فقط — كل ما يخص الإناث (البنت، الزوجة، الأخت، الأم) في شجرة النساء
/// (طلب المالك ٢٠٢٦-١٠-٢٥ «اي شي يخص الاناث يكون بشجرة النساء»)
struct TreeEditRequestView: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    // لون القسم الذي فُتح منه الطلب (الشجرة، الرئيسية، الإدارة…) — الكحلي «إطار» يتبعه
    @Environment(\.dsSection) private var section
    private var chromeInk: Color { DS.Color.primary.dsChrome(in: section) }

    let member: FamilyMember
    let action: TreeEditAction

    /// مع `.add`: ابن أو أكثر، لكل ابن «متوفّى» — طلب لكل ابن (طلب المالك ٢٠٢٦-١٠-٢٥)
    @State private var sons: [DSAddEntry] = [DSAddEntry()]
    @State private var isSendingSons = false
    /// كم طلباً أُرسل — لرسالة النجاح
    @State private var sentCount = 0
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

    private var actionColor: Color {
        switch action {
        case .add: return DS.Color.palm
        case .editName: return DS.Color.info
        case .editPhone: return chromeInk
        case .editBirth: return DS.Color.palm
        case .deceased: return DS.Color.textTertiary
        case .addDeathDate: return DS.Color.textTertiary
        case .addPhoto: return chromeInk
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

    /// الأبناء المكتوبة أسماؤهم (الصفّ الفارغ لا يُرسل)
    private var namedSons: [DSAddEntry] { sons.filter { !$0.trimmedName.isEmpty } }

    private var canSubmit: Bool {
        guard !adminRequestVM.isLoading, !isUploadingPhoto, !isSendingSons else { return false }
        switch action {
        case .add:
            return !namedSons.isEmpty
        case .editName:
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
            subtitle: member.displayFullName,
            icon: action.iconName,
            tint: headerTint,
            actionTitle: submitTitle,
            actionIcon: "paperplane.fill",
            canSubmit: canSubmit,
            isBusy: adminRequestVM.isLoading || isUploadingPhoto || isSendingSons,
            note: action == .add ? L10n.t("لكل ابن طلب يُراجَع وحده", "One request per son, each reviewed on its own")
                                 : L10n.t("يصل الطلب للإدارة لمراجعته", "Sent to the admins for review"),
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { submit() },
            onCancel: { dismiss() }
        ) {
            // قسم واحد بلغة مربّعات العمل («أسلوب واحد»): رأسه نوع الطلب بلونه، ثم العضو، ثم الحقل، ثم الملاحظات
            requestSection
            if action == .add {
                // «ابن» — اسم أو أكثر، ولكل ابن «متوفّى» (ذكور فقط: البنات والزوجات في شجرة النساء)
                DSAddEntriesSection(entries: $sons, title: L10n.t("الأبناء", "Sons"), icon: "person.badge.plus",
                                    tint: actionColor, index: 1,
                                    rowLabel: { _ in L10n.t("ابن", "Son") },
                                    placeholder: L10n.t("اسم الابن الأول", "Son's first name"),
                                    newGender: "male")
                DSComposerSection(title: L10n.t("ملاحظات", "Notes"), icon: "note.text",
                                  tint: DS.Color.primary, index: 2) {
                    notesField
                }
            }
        }
            .dsAlert(L10n.t("تم الإرسال", "Request Sent"), isPresented: $showSuccessAlert, moment: .sentForApproval) {
                Button(L10n.t("حسناً", "OK")) { dismiss() }
            } message: {
                Text(sentCount > 1
                     ? L10n.t("وصلت طلباتك (\(sentCount)) للإدارة — كلٌّ يُراجَع وحده، ويُضاف الابن عند قبول طلبه.",
                              "Your \(sentCount) requests reached the admins — each is reviewed on its own.")
                     : L10n.t("تم إرسال طلبك للإدارة وسيتم مراجعته قريباً.",
                              "Your request has been sent to admin for review."))
            }
            .dsAlert(L10n.t("تعذر الإرسال", "Failed to Send"), isPresented: $showErrorAlert) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(errorMessage ?? L10n.t(
                    "تعذر إرسال الطلب. حاول مرة أخرى.",
                    "Failed to send request. Please try again."
                ))
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

    private var currentDraft: Draft {
        Draft(
            primaryText: primaryText.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: localPhoneDigits.isEmpty ? "" : "\(phoneCountry.id)|\(localPhoneDigits)",
            birthDay: DateHelper.format(birthDate),
            deathDay: DateHelper.format(deathDate)
        )
    }

    /// نص أو تاريخ أو رقم أو صورة أو ابن مكتوب تختلف عمّا فُتح عليه المربّع — «إلغاء» يسأل قبل التجاهل
    private var hasUnsavedChanges: Bool {
        guard let startDraft else { return false }
        return selectedPhoto != nil || currentDraft != startDraft
            || sons.contains { !$0.isBlank } || sons.count > 1
    }

    /// «إرسال الطلب»، ومع أكثر من ابن «إرسال ٣ طلبات»
    private var submitTitle: String {
        let n = namedSons.count
        return action == .add && n > 1 ? L10n.t("إرسال ", "Send ") + DSRequestCount.text(n)
                                       : L10n.t("إرسال الطلب", "Submit Request")
    }

    // MARK: - القسم

    /// قسم الطلب (`DSComposerSection`): رأسه نوع الطلب (رمزه ولونه)، صفّ العضو، حقل الطلب، والملاحظات —
    /// نفس أقسام وحقول مربّعات الإضافة (`DSRow` / `DSComposerField` / `DSFieldBox`)
    private var requestSection: some View {
        DSComposerSection(title: L10n.t(action.arabicLabel, action.englishLabel),
                          icon: action.iconName, tint: actionColor, index: 0) {
            // مع «ابن»: سطر «لمن» تحت العضو (طلب المالك ٢٠٢٦-١٠-٢٥ «حط توضيح»)، والأسماء والملاحظات في قسميهما
            DSRow(icon: "person.fill", tint: actionColor, title: member.displayFullName,
                  subtitle: action == .add ? L10n.t("ابن أو أكثر لـ«\(member.firstName)»",
                                                    "One or more sons of «\(member.firstName)»")
                                           : nil) { EmptyView() }
            primaryField
            if action != .add { notesField }
        }
    }

    // MARK: - Primary Field

    @ViewBuilder
    private var primaryField: some View {
        switch action {
        case .add:
            // الأسماء في قسم «الأبناء» (`DSAddEntriesSection`)
            EmptyView()
        case .editName:
            DSComposerField(icon: "pencil", label: L10n.t("الاسم الجديد", "New Name"),
                            placeholder: L10n.t("اكتب الاسم الجديد...", "Enter new name..."),
                            text: $primaryText, tint: actionColor)
        case .editBirth:
            dateRow(icon: "gift.fill", tint: DS.Color.warning,
                    title: L10n.t("تاريخ الميلاد الصحيح", "Correct Birth Date"), date: $birthDate)
        case .editPhone:
            DSFieldBox(L10n.t("الرقم الجديد", "New Phone Number")) {
                DSPhoneField(
                    country: $phoneCountry,
                    digits: $localPhoneDigits,
                    placeholder: L10n.t("رقم الهاتف", "Phone number"),
                    compact: true,
                    bordered: false
                )
            }
        case .deceased, .addDeathDate:
            dateRow(icon: "calendar", tint: DS.Color.error,
                    title: L10n.t("تاريخ الوفاة", "Date of Death"), date: $deathDate)
        case .addPhoto:
            // عنوان الحقل بخط عناوين حقول المربّعات، والصورة بلا صندوق حقل حولها (مثل «إضافة ابن»)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(L10n.t("الصورة المقترحة", "Suggested Photo"))
                    .dsFieldFont(DSBox.fieldLabelSize, weight: .heavy)
                    .foregroundColor(DS.Color.fieldLabel)
                DSProfilePhotoPicker(
                    selectedImage: $selectedPhoto,
                    title: L10n.t("اضغط لاختيار صورة", "Tap to choose a photo"),
                    trailing: nil,
                    compactEmptyState: true
                )
                .frame(maxWidth: .infinity)
            }
        case .delete, .other:
            EmptyView()
        }
    }

    /// صفّ تاريخ يفتح مربّع التاريخ الموحّد بالمنتصف (حتى اليوم) — نفس صفوف التاريخ في «إضافة ابن»
    private func dateRow(icon: String, tint: Color, title: String, date: Binding<Date>) -> some View {
        Button {
            dsPresentDatePicker(title: title, initial: date.wrappedValue, allowClear: false) { picked in
                if let picked { date.wrappedValue = picked }
            }
        } label: {
            DSRow(icon: icon, tint: tint, title: title, subtitle: DSDateText.display(date.wrappedValue)) {
                DSStateIcon("pencil", tint: DS.Color.primary, size: DSBox.fieldIcon)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.t("يفتح اختيار التاريخ", "Opens the date picker"))
    }

    // MARK: - Notes / Reason

    /// الملاحظات — حقل المربّعات متعدد الأسطر (يكبر بالكتابة حتى ٤ أسطر)
    private var notesField: some View {
        DSComposerField(icon: notesRequired ? "text.bubble.fill" : "note.text",
                        label: notesLabel, placeholder: notesPlaceholder,
                        text: $notes, tint: notesRequired ? actionColor : DS.Color.primary, multiline: true)
    }

    /// الملاحظات مطلوبة في الحذف و«أخرى»
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
            submitSons(namedSons, notes: cleanNotes)
            return

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
            // يوم التقويم المحلي — ISO8601 بـ withFullDate كان بتوقيت غرينتش (يوم قبل بين ١٢–٣ فجراً)
            payload = TreeEditPayload.make(
                action: .deceased,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                deathDate: DateHelper.format(deathDate),
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
            // يوم التقويم المحلي — ISO8601 بـ withFullDate كان بتوقيت غرينتش (يوم قبل بين ١٢–٣ فجراً)
            payload = TreeEditPayload.make(
                action: .editBirth,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                newBirthDate: DateHelper.format(birthDate),
                notes: cleanNotes.isEmpty ? nil : cleanNotes
            )

        case .addDeathDate:
            // يوم التقويم المحلي — ISO8601 بـ withFullDate كان بتوقيت غرينتش (يوم قبل بين ١٢–٣ فجراً)
            payload = TreeEditPayload.make(
                action: .addDeathDate,
                targetMemberId: member.id.uuidString,
                targetMemberName: member.fullName,
                deathDate: DateHelper.format(deathDate),
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

    /// «ابن» أو أكثر — طلب لكل ابن بمسار الطلبات نفسه (`newMemberName`: يُضاف تلقائياً عند قبول طلبه). القبول لا يكتب
    /// الوفاة، فالمتوفّى يُكتب في ملاحظة طلبه بوضوح لتسجّل الإدارة وفاته بعد القبول. ما يُرسل يخرج من المربّع —
    /// إن تعذّر طلب بقي هو وما بعده ولا يتكرّر ما أُرسل
    private func submitSons(_ list: [DSAddEntry], notes: String) {
        guard !list.isEmpty, !isSendingSons else { return }
        isSendingSons = true
        Task {
            var sent = 0
            for son in list {
                var lines: [String] = []
                if son.deceased {
                    lines.append(L10n.t("الحالة: متوفّى — بعد القبول سجّل وفاته من تفاصيله.",
                                        "Status: deceased — after approval, record his death from his details."))
                }
                if !notes.isEmpty { lines.append(notes) }
                let payload = TreeEditPayload.make(
                    action: .add,
                    targetMemberId: member.id.uuidString,
                    targetMemberName: member.fullName,
                    parentMemberId: member.id.uuidString,
                    parentMemberName: member.fullName,
                    newMemberName: son.trimmedName,
                    notes: lines.isEmpty ? nil : lines.joined(separator: "\n")
                )
                guard await adminRequestVM.submitTreeEditRequest(payload: payload) else {
                    isSendingSons = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    errorMessage = sent > 0
                        ? L10n.t("أُرسل \(sent) وتعذّر الباقي — حاول إرسالهم مرة أخرى.",
                                 "\(sent) sent, the rest failed — try sending them again.")
                        : nil
                    showErrorAlert = true
                    return
                }
                sent += 1
                withAnimation(DS.Anim.snappy) { sons.removeAll { $0.id == son.id } }
            }
            isSendingSons = false
            sentCount = sent
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showSuccessAlert = true
        }
    }
}
