import SwiftUI

// مربّعا العضو المعلّق — نُقلا من AdminPendingRequestsView.swift (٢٠٢٦-١٠-٠٧) بعد حذف الشاشة القديمة
// غير المستعملة `AdminPendingRequestsView`؛ يفتحهما «طلبات المراجعة» و«تفعيل الحسابات» ودليل الأعضاء.

// MARK: - ربط مباشر بعضو موجود بالشجرة (swipe right)

/// عدد الأعضاء الظاهرين في قائمة الربط قبل «عرض المزيد» — صفوف عادية لا قائمة كسولة
/// حتى يُقاس ارتفاع المربّع كاملاً (نفس ملاحظة مربّعات الاختيار)
private let linkCandidatesPageSize = 40

/// صورة الحرف الأول للعضو في صفوف المربّعات (بحجم أيقونة الحقل) — صورة العضو الموحّدة
private func memberInitialBadge(_ name: String, tint: Color) -> some View {
    DSMemberAvatar(name: name, avatarUrl: nil, size: DS.Icon.row, roleColor: tint)
}

/// «ربط بعضو موجود» — نفس تصميم المربّعات الموحّد (طلب المالك): رأس كحلي، الحساب المعلّق
/// ثم البحث في أعضاء الشجرة، و«ربط» / «إلغاء» أسفل المربّع
struct LinkToExistingMemberSheet: View {
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var adminRequestVM: AdminRequestViewModel
    @Environment(\.dismiss) var dismiss
    /// «تقليل الحركة» (توصية أبل): صف المختار يظهر بتلاشٍ فقط بلا انزلاق ولا تكبير
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pendingMember: FamilyMember
    /// الأقرب لاسمه (مطابقات الشجرة من «طلبات المراجعة») — تظهر أولاً، وتُستبعد من «كل الأعضاء»
    var suggested: [FamilyMember] = []

    @State private var searchText = ""
    @State private var selectedMember: FamilyMember? = nil
    @State private var showConfirm = false
    @State private var displayLimit = linkCandidatesPageSize

    private var candidates: [FamilyMember] {
        let all = memberVM.allMembers.filter {
            $0.role != .pending &&
            $0.hasName &&
            $0.id != pendingMember.id &&
            $0.isDeceased != true
        }
        if searchText.isEmpty {
            // بلا تكرار: المقترحون في قسمهم أعلى
            let suggestedIds = Set(suggested.map(\.id))
            return all.filter { !suggestedIds.contains($0.id) }
        }
        return all.filter { $0.fullName.localizedCaseInsensitiveContains(searchText) }
    }

    /// المقترحون الأحياء غير المعلّقين فقط
    private var visibleSuggestions: [FamilyMember] {
        suggested.filter { $0.role != .pending && $0.hasName && $0.isDeceased != true && $0.id != pendingMember.id }
    }

    var body: some View {
        DSComposer(
            title: L10n.t("ربط بالشجرة", "Link to Tree"),
            subtitle: pendingMember.displayFullName,
            icon: "link.badge.plus",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("ربط", "Link"),
            actionIcon: "link",
            canSubmit: selectedMember != nil,
            isBusy: adminRequestVM.isLoading,
            // عضو مختار ولم يُربط بعد → «إلغاء» يسأل قبل التجاهل (توصية أبل)
            hasUnsavedChanges: selectedMember != nil,
            onSubmit: { showConfirm = true },
            onCancel: { dismiss() }
        ) {
            linkPreview
            if searchText.isEmpty && !visibleSuggestions.isEmpty {
                suggestionsSection
            }
            candidatesSection
        }
        .animation(DS.Anim.snappy, value: selectedMember?.id)
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        // بحث جديد → نبدأ من أول النتائج
        .onChange(of: searchText) { _ in displayLimit = linkCandidatesPageSize }
        .dsAlert(
            L10n.t("تأكيد الربط", "Confirm Link"),
            isPresented: $showConfirm
        ) {
            Button(L10n.t("ربط", "Link"), role: .none) {
                guard let target = selectedMember else { return }
                Task {
                    await adminRequestVM.mergeMemberIntoTreeMember(
                        newMemberId: pendingMember.id,
                        existingTreeMemberId: target.id
                    )
                    dismiss()
                }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            if let target = selectedMember {
                Text(L10n.t(
                    "سيُربط حساب \(pendingMember.firstName) بسجل \(target.fullName) الموجود بالشجرة.\nسيحتفظ بموقعه وأبنائه وبياناته.",
                    "Account \(pendingMember.firstName) will be linked to \(target.fullName)'s existing tree record. Position, children and data will be preserved."
                ))
            }
        }
    }

    // MARK: مخطط الربط — الحساب الجديد ← عضو الشجرة (طلب المالك ٢٠٢٦-١٠-٠١)

    /// بطاقة واحدة: الحساب الجديد فوق، ثم سهم، ثم عضو الشجرة المختار (أو مكانه منقّطاً)
    private var linkPreview: some View {
        VStack(spacing: 0) {
            linkPerson(name: pendingMember.displayFullName,
                       caption: L10n.t("الحساب الجديد", "New account"),
                       ring: DS.Color.warning)

            // الوصلة
            HStack(spacing: DS.Spacing.sm) {
                Rectangle()
                    .fill(DS.Color.textTertiary.opacity(DS.Opacity.tintStroke))
                    .frame(width: DS.Spacing.xxs, height: DS.Spacing.lg)
                    // تحت منتصف صورة الشخص
                    .padding(.leading, (DS.Icon.avatar - DS.Spacing.xxs) / 2)
                Image(systemName: "arrow.down")
                    .dsGlyph(DS.Glyph.xs, weight: .heavy)
                    .foregroundColor(selectedMember == nil ? DS.Color.textTertiary : DS.Color.success)
                    .accessibilityHidden(true)
                Text(L10n.t("يُربط بـ", "Links to"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, DS.Spacing.xxs)

            if let selected = selectedMember {
                linkPerson(name: selected.displayFullName,
                           caption: L10n.t("عضو الشجرة", "Tree member"),
                           ring: DS.Color.success) {
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) { selectedMember = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dsGlyph(DS.Glyph.xl, weight: .regular)
                            .foregroundColor(DS.Color.textTertiary)
                            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                            .contentShape(Rectangle())
                            .padding(-(DS.Spacing.md - DS.Spacing.xxs))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.t("إلغاء الاختيار", "Clear selection"))
                }
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Circle()
                        .strokeBorder(DS.Color.textTertiary.opacity(DS.Opacity.selectedStroke),
                                      style: StrokeStyle(lineWidth: DS.Border.widthBold, dash: [DS.Spacing.xs, DS.Spacing.xs - 1]))
                        .frame(width: DS.Icon.avatar, height: DS.Icon.avatar)
                        .overlay(Image(systemName: "questionmark")
                            .dsGlyph(DS.Glyph.md)
                            .foregroundColor(DS.Color.textTertiary))
                        .accessibilityHidden(true)
                    Text(L10n.t("اختر عضو الشجرة من القائمة", "Pick the tree member below"))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        // البطاقة الواحدة
        .dsCard(padding: DS.Spacing.md)
        .dsStaggerIn(0)
    }

    private func linkPerson(name: String, caption: String, ring: Color) -> some View {
        linkPerson(name: name, caption: caption, ring: ring) { EmptyView() }
    }

    /// شخص في مخطط الربط: أول حرف بحلقة اللون + الاسم + وصفه
    private func linkPerson<Trailing: View>(name: String, caption: String, ring: Color,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(String(name.trimmingCharacters(in: .whitespaces).prefix(1)))
                .dsFont(.title)
                .foregroundColor(AppSection.admin.ink)
                .frame(width: DS.Icon.avatar, height: DS.Icon.avatar)
                .background(Circle().fill(AppSection.admin.ink.opacity(DS.Opacity.tintFillSoft)))
                .overlay(Circle().strokeBorder(ring.dsReadableGlyph, lineWidth: DS.Border.widthBold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(caption)
                    .dsFont(.caption)
                    .foregroundColor(ring.dsReadableGlyph)
                Text(name)
                    .dsFieldFont(.headline)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            trailing()
        }
    }

    // MARK: الأقرب لاسمه (من مطابقات الشجرة)

    private var suggestionsSection: some View {
        DSComposerSection(title: L10n.t("الأقرب لاسمه", "Closest names"),
                          icon: "sparkles",
                          tint: DS.Color.success,
                          trailing: "\(visibleSuggestions.count)",
                          index: 1) {
            ForEach(visibleSuggestions) { member in
                candidateRow(member)
            }
        }
    }

    // MARK: البحث + أعضاء الشجرة

    private var candidatesSection: some View {
        let list = candidates
        let visible = Array(list.prefix(displayLimit))
        return DSComposerSection(title: searchText.isEmpty && !visibleSuggestions.isEmpty
                                        ? L10n.t("كل أعضاء الشجرة", "All tree members")
                                        : L10n.t("أعضاء الشجرة", "Tree Members"),
                                 icon: "person.3.fill",
                                 tint: AppSection.admin.ink,
                                 index: 2) {
            DSComposerField(icon: "magnifyingglass",
                            label: L10n.t("بحث", "Search"),
                            placeholder: L10n.t("ابحث عن عضو...", "Search member..."),
                            text: $searchText)
                .overlay(alignment: .trailing) { clearSearchButton }

            ForEach(visible) { member in
                candidateRow(member)
            }

            if list.count > visible.count {
                showMoreButton(remaining: list.count - visible.count)
            }
        }
    }

    @ViewBuilder
    private var clearSearchButton: some View {
        if !searchText.isEmpty {
            Button { searchText = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .dsGlyph(DS.Glyph.lg, weight: .regular)
                    .foregroundColor(DS.Color.textTertiary)
                    // مساحة ضغط ٤٤ (توصية أبل) بلا هامش — الرمز في نفس موضعه (كان ٣٦ + هامش ٤)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("مسح البحث", "Clear search"))
        }
    }

    private func candidateRow(_ member: FamilyMember) -> some View {
        let isSelected = selectedMember?.id == member.id
        return Button {
            withAnimation(DS.Anim.snappy) {
                selectedMember = isSelected ? nil : member
            }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Group {
                    if isSelected {
                        DSFieldIcon(name: "checkmark", tint: DS.Color.success)
                    } else {
                        memberInitialBadge(member.fullName, tint: AppSection.admin.ink)
                    }
                }
                .accessibilityHidden(true)
                Text(member.displayFullName)
                    .dsFieldFont(DSBox.fieldValueSize, weight: isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? DS.Color.textPrimary : DS.Color.fieldValue)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.xl, weight: .semibold)
                        .foregroundColor(DS.Color.success)
                        // «تقليل الحركة»: تلاشٍ فقط بلا تكبير
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(DS.Color.success.opacity(isSelected ? DS.Opacity.selectedStroke : 0),
                                  lineWidth: DS.Border.widthBold)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// «عرض المزيد» — الشريحة الموحّدة في وسط السطر
    private func showMoreButton(remaining: Int) -> some View {
        DSChipButton(L10n.t(
            "عرض المزيد (\(remaining) متبقي)",
            "Show more (\(remaining) remaining)"
        ), icon: "chevron.down", tint: AppSection.admin.ink) {
            withAnimation(DS.Anim.snappy) { displayLimit += linkCandidatesPageSize }
        }
        .frame(maxWidth: .infinity)
    }
}

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
