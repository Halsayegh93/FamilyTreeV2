import SwiftUI

// مربّع رقم العضو المعلّق — نُقل من AdminPendingRequestsView.swift (٢٠٢٦-١٠-٠٧) بعد حذف الشاشة القديمة
// غير المستعملة `AdminPendingRequestsView`؛ يفتحهما «طلبات المراجعة» و«تفعيل الحسابات» ودليل الأعضاء.

/// صورة الحرف الأول للعضو في صفوف المربّعات (بحجم أيقونة الحقل) — صورة العضو الموحّدة
private func memberInitialBadge(_ name: String, tint: Color) -> some View {
    DSMemberAvatar(name: name, avatarUrl: nil, size: DS.Icon.row, roleColor: tint)
}

// «ربط بالشجرة» و«ربط بشجرة النساء» القديمان حُذفا (R2، ٢٠٢٦-١١-٢٧): الربط كله من مربّعات «الوارد» الصغيرة
// (`AdminJoinBoxes.swift`) بنفس النداءات (merge_member_into_tree · link_woman_account · approveMember).

// MARK: - مربّع تعديل / إضافة رقم فعلي لعضو معلّق
/// نفس تصميم المربّعات الموحّد (طلب المالك): رأس كحلي، العضو ثم الرقم الجديد،
/// و«حفظ» / «إلغاء» أسفل المربّع
struct PendingMemberPhoneSheet: View {
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    let member: FamilyMember
    /// عند true يفعّل العضو بعد حفظ الرقم (يُستخدم في «صحة الشجرة»)
    var activateOnSave: Bool = false

    @State private var selectedCountry: KuwaitPhone.Country = KuwaitPhone.defaultCountry
    @State private var localDigits: String = ""
    @State private var errorBanner: String? = nil

    private var canSave: Bool {
        !localDigits.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !adminRequestVM.isLoading
    }

    /// الرقم الذي يُفتح عليه المربّع (نفس تعبئة onAppear) — للمقارنة بما أُدخل
    private var start: (country: KuwaitPhone.Country, localDigits: String) {
        KuwaitPhone.detectCountryAndLocal(member.phoneNumber)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("رقم العضو", "Member Number"),
            subtitle: member.displayFullName,
            icon: "phone.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: canSave,
            isBusy: adminRequestVM.isLoading,
            // رقم أو دولة مختلفة عمّا فُتح عليه → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: localDigits != start.localDigits || selectedCountry != start.country,
            onSubmit: { save() },
            onCancel: { dismiss() }
        ) {
            memberSection
            numberSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear {
            let detected = start
            selectedCountry = detected.country
            localDigits = detected.localDigits
            focused = true
        }
    }

    // MARK: العضو

    private var memberSection: some View {
        DSComposerSection(title: L10n.t("العضو", "Member"),
                          icon: "person.fill",
                          tint: DS.Color.warning,
                          index: 0) {
            HStack(spacing: DS.Spacing.sm) {
                memberInitialBadge(member.fullName, tint: DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(member.displayFullName)
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                        .lineLimit(2)
                    // الرقم معزول باتجاه LTR — بدونه يظهر في السطر العربي «50011223 965+»
                    Text(L10n.t("الرقم الحالي: ", "Current: ")
                         + "\u{2066}" + KuwaitPhone.display(member.phoneNumber) + "\u{2069}")
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: الرقم الجديد (الدولة + الرقم المحلي)

    private var numberSection: some View {
        DSComposerSection(title: L10n.t("الرقم الفعلي الجديد", "New real number"),
                          icon: "number",
                          tint: DS.Color.success,
                          index: 1) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "phone.fill", tint: DS.Color.sea)
                    .accessibilityHidden(true)
                DSPhoneField(
                    country: $selectedCountry,
                    digits: $localDigits,
                    placeholder: String(repeating: "X", count: selectedCountry.maxDigits),
                    compact: true,
                    bordered: false
                )
            }
            .dsRowBox()

            Text(activateOnSave
                 ? L10n.t(
                    "سيُضاف الرقم ويُفعّل الحساب مباشرة بعد الحفظ.",
                    "The number will be added and the account activated right after saving.")
                 : L10n.t(
                    "يُحدَّث رقم العضو فقط — يبقى الطلب معلّقاً لتربطه بالشجرة أو ترفضه لاحقاً.",
                    "Only updates the member's number — the request stays pending so you can link or reject it later."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorBanner {
                // الملاحظة الموحّدة بالأحمر
                DSNoteCard(errorBanner, icon: "exclamationmark.triangle.fill", tint: DS.Color.error)
            }
        }
    }

    private func save() {
        errorBanner = nil
        Task {
            let ok = await adminRequestVM.updatePendingMemberPhone(
                memberId: member.id,
                country: selectedCountry,
                localDigits: localDigits,
                activate: activateOnSave
            )
            if ok {
                dismiss()
            } else {
                errorBanner = adminRequestVM.errorMessage
                adminRequestVM.errorMessage = nil
            }
        }
    }
}
