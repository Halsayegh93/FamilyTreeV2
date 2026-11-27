import SwiftUI

// MARK: - «الحساب» و«إجراءات الإدارة» في ورقة العضو (V2-3، وفصل F4 — طلب المالك ٢٠٢٦-١١-٢٦: «اهم شي نفصل الأمور
// الادارية عن الاعضاء»)
//
// (V3: «الحساب» صار المجموعة الثالثة في «العضو» — `AdminMemberAccountGroup` في `AdminMemberCardGroups.swift` — وبقي هنا
// نصوصه وشروطه `AdminMemberAccountSection`، والأجهزة للاطلاع `AdminMemberDevicesFacts`؛ و«إجراءات الإدارة» بشريط عنوان كحلي
// أوله «طلبات عنه» ثم «رقم الهاتف».)
// ١) `AdminMemberAccountSection` — «الحساب» (بترولي) حقائق فقط: الهاتف (يُعدَّل بمربّعه لمن يعدّل — تعديل بيانات) ·
//    «تسجيل في التطبيق» حبّة الحال («مسجّل ✓» / «غير مسجّل» / «موقوف») · آخر دخول (وتحته استخدامه) · الأجهزة بعددها
//    (لمن يراها ولا يسجّل خروجها: تنفتح أسماؤها تحته للاطلاع). لا زرّ أمر هنا.
// ٢) `AdminMemberAdminSection` — «إجراءات الإدارة»: عنوان بشريط كحلي وبطاقة بإطار كحلي، فيها كل أمر بترتيبه
//    (`AdminMemberSheetLogic.adminCard`): الصورة (`AdminMemberPhotoActions`) · «تسجيل في التطبيق» («سجّل» بتأكيد) ·
//    الأجهزة بـ«تسجيل خروج» لكل جهاز (`canManageDevices`) · «إيقاف الحساب»/«رفع الإيقاف» (`canFreezeMembers`) · «منع الرقم
//    من التسجيل» (`canManageBannedPhones` — يفتح «التسجيل والمنع» برقمه) · «حذف العضو نهائياً» آخرها بالأحمر
//    (`canDeleteMembers`). على ورقتك لا تُرسم البطاقة أصلاً (يبقى سطر القفل).
// الصلاحيات والنداءات كما هي: كل فعل يمرّ بالورقة (`ask` = التأكيد، `openBox` = المربّعات، `openBans` = الصفحة).

/// نصوص «الحساب» وشروطه — تقرؤها مجموعة «الحساب» (`AdminMemberAccountGroup`) و«إجراءات الإدارة» (V3: صارت المجموعة
/// الثالثة في «العضو»، حقائق فقط، والرقم بأوامره في «إجراءات الإدارة»)
enum AdminMemberAccountSection {
    static func registerWord(_ status: AdminMemberStatus?) -> String {
        switch status {
        case .registered: return L10n.t("مسجّل", "Registered")
        case .frozen: return L10n.t("موقوف", "Suspended")
        case .pendingJoin: return L10n.t("قيد المراجعة", "Under review")
        case .treeOnly, .deceased: return L10n.t("غير مسجّل", "Not registered")
        case nil: return AdminStoreHealthText.placeholder
        }
    }

    static func registerTone(_ status: AdminMemberStatus?) -> AdminPillTone {
        switch status {
        case .registered: return .ok
        case .frozen: return .error
        default: return .off
        }
    }

    /// يُسجَّل في التطبيق من «إجراءات الإدارة»؟ — نفس شرط الزرّ السابق حرفياً
    @MainActor
    static func canRegister(member: FamilyMember, facts: AdminMemberSheetFacts, canEdit: Bool, isOther: Bool,
                            liveStatus: FamilyMember.MemberStatus?) -> Bool {
        let phone = (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return canEdit && isOther && facts.status != .frozen && !phone.isEmpty && member.role != .pending
            && (liveStatus ?? member.status) != .active && facts.status != .registered
    }

    /// «يحتاج رقم هاتف أولاً» تحت «التطبيق» لغير المسجّل بلا رقم
    @MainActor
    static func registerNote(member: FamilyMember, facts: AdminMemberSheetFacts) -> String? {
        let phone = (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard facts.status == .treeOnly, phone.isEmpty else { return nil }
        return L10n.t("يحتاج رقم هاتف أولاً", "Needs a phone number first")
    }
}

/// «الأجهزة · 2» في «الحساب» لمن يراها ولا يسجّل خروجها — «⌄» يفتح أسماءها للاطلاع؛ التحميل «—»، والفشل «تعذّر التحميل»
/// يعيد الجلب (كما كانت في «الحساب» قبل V3)
struct AdminMemberDevicesFacts: View {
    let devices: [NotificationViewModel.LinkedDevice]?
    let failed: Bool
    @Binding var open: Bool
    let retry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let title = L10n.t("الأجهزة", "Devices")
        VStack(spacing: 0) {
            if let devices {
                if failed {
                    AdminMemberTapRow(hint: AdminStoreHealthText.retry, action: retry) {
                        AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title) {
                            AdminStatePill(title: AdminStoreHealthText.failed, tone: .unknown, icon: "arrow.clockwise")
                        }
                    }
                } else if devices.isEmpty {
                    AdminMemberRow(icon: "iphone.slash", tint: DS.Color.sea, title: title,
                                   subtitle: L10n.t("لا تصله الإشعارات", "Gets no notifications"),
                                   value: L10n.t("لا أجهزة", "None"))
                } else {
                    AdminMemberTapRow(hint: open ? L10n.t("يطوي الأجهزة", "Hides the devices")
                                                 : L10n.t("يعرض الأجهزة", "Shows the devices"),
                                      action: { withAnimation(reduceMotion ? nil : DS.Anim.snappy) { open.toggle() } }) {
                        AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title,
                                       value: "\(devices.count)", valueIsNumber: true) {
                            Image(systemName: "chevron.down")
                                .dsGlyph(DS.Glyph.sm)
                                .foregroundColor(DS.Color.textTertiary)
                                .rotationEffect(.degrees(open ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityValue(open ? L10n.t("ظاهرة", "Shown") : L10n.t("مطويّة", "Collapsed"))
                    if open {
                        ForEach(devices) { device in
                            AdminMemberDeviceRow(device: device, canSignOut: false, busy: false, signOut: {})
                        }
                    }
                }
            } else {
                AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title, value: AdminStoreHealthText.placeholder)
                    .accessibilityValue(AdminStoreHealthText.loading)
            }
        }
    }
}

/// جهاز: الاسم و«آخر استخدام …»، و«تسجيل خروج» حمراء بإطار لمن يملكها
struct AdminMemberDeviceRow: View {
    let device: NotificationViewModel.LinkedDevice
    let canSignOut: Bool
    let busy: Bool
    let signOut: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(verbatim: device.displayName)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: L10n.t("آخر استخدام ", "Last used ") + AdminMemberSheetFacts.dateText(iso: device.updatedAt))
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DS.Spacing.sm)
            if busy {
                ProgressView()
                    .scaleEffect(DS.Spinner.chipScale)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            } else if canSignOut {
                AdminPillButton(title: L10n.t("تسجيل خروج", "Sign out"), style: .reject, action: signOut)
                    .fixedSize()
                    .accessibilityLabel(L10n.t("تسجيل خروج \(device.displayName)", "Sign out \(device.displayName)"))
                    .accessibilityHint(L10n.t("يسأل قبل الخروج", "Asks first"))
            }
        }
        .padding(.leading, AdminRowDivider.iconInset)
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
    }
}

// MARK: - «إجراءات الإدارة»

struct AdminMemberAdminSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let card: AdminMemberSheetLogic.AdminCard
    /// الرقم المطبَّع لصفحة «التسجيل والمنع» (nil = مخفي أو غير صالح — لا صفّ)
    let banPrefill: String?
    /// منع رقمه الساري (للعرض فقط)
    let ban: BannedPhone?
    let devices: [NotificationViewModel.LinkedDevice]?
    let noDevices: Bool
    let busy: String?
    let ask: (AdminMemberConfirm) -> Void
    let openBox: (AdminMemberBox) -> Void
    let openBans: (String) -> Void
    @Binding var photoWorking: Bool
    /// V3: شريط «طلبات عنه» أول البطاقة (nil = لمن لا يقرّر طلبات الشجرة)
    var requests: AnyView? = nil

    private var frozen: Bool { facts.status == .frozen }
    private var phone: String { (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    /// V3 (`v3-b.png`): بطاقة منفصلة بشريط عنوان كحلي (درع ذهبي + «إجراءات الإدارة»)، أولها «طلبات عنه» ثم الأوامر
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "checkmark.shield")
                    .dsGlyph(DS.Glyph.md, weight: .semibold)
                    .foregroundColor(DS.Color.accentLight)
                    .accessibilityHidden(true)
                Text(Self.title)
                    .dsFont(DS.Hub.familyBranchTitle)
                    .foregroundColor(DS.Color.textOnPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Hub.band)
            if let requests { requests }
            if !card.items.isEmpty {
                AdminRowsCardBody {
                    ForEach(card.items, id: \.self) { item in
                        row(item)
                    }
                }
                .padding(.horizontal, DS.Hub.cardPadding)
                .padding(.vertical, DS.Spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(DS.Color.cardBackground))
        .clipShape(shape)
        .overlay(shape.strokeBorder(DS.Hub.memberAdminStroke, lineWidth: DS.Border.widthBold))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(Self.title))
    }

    static var title: String { L10n.t("إجراءات الإدارة", "Admin actions") }

    @ViewBuilder
    private func row(_ item: AdminMemberSheetLogic.AdminItem) -> some View {
        switch item {
        case .phone:
            // «رقم الهاتف» (نُقل من «العضو»): تعديله بمربّع الرقم، و«امسح» لمن لا حساب دخول له
            HStack(spacing: DS.Spacing.sm) {
                AdminMemberTapRow(hint: phone.isEmpty ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"),
                                  action: { openBox(.phone(member)) }) {
                    AdminMemberRow(icon: "phone.fill", tint: DS.Color.sea, title: L10n.t("رقم الهاتف", "Phone number"),
                                   subtitle: phone.isEmpty ? L10n.t("إضافة رقم", "Add a number")
                                                           : L10n.t("تعديل الرقم أو مسحه", "Edit or clear the number"),
                                   showsChevron: true,
                                   busy: busy == AdminMemberConfirm.unlinkPhone.id || busy == AdminMemberConfirm.clearPhone.id)
                }
                if !phone.isEmpty && facts.account == nil {
                    AdminPillButton(title: L10n.t("امسح", "Clear"), style: .reject) { ask(.unlinkPhone) }
                        .fixedSize()
                        .accessibilityLabel(L10n.t("مسح رقم الهاتف", "Clear the phone number"))
                        .accessibilityHint(L10n.t("يسأل أولاً", "Asks first"))
                }
            }
        case .photo:
            AdminMemberPhotoActions(member: member, hasLogin: facts.account != nil, noDevices: noDevices,
                                    askChange: { openBox(.photoRequest(member)) }, working: $photoWorking)
        case .register:
            AdminMemberRow(icon: "iphone", tint: DS.Color.sea, title: L10n.t("تسجيل في التطبيق", "Register in the app"),
                           subtitle: L10n.t("يتمكن من الدخول برقمه", "They can sign in with their number"),
                           busy: busy == AdminMemberConfirm.register.id) {
                AdminPillButton(title: L10n.t("سجّل", "Register"), style: .navy) { ask(.register) }
                    .accessibilityLabel(L10n.t("تسجيل في التطبيق", "Register in the app"))
                    .accessibilityHint(L10n.t("يسأل قبل التسجيل", "Asks first"))
            }
        case .devices:
            VStack(spacing: 0) {
                AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: L10n.t("أجهزته", "Their devices"),
                               subtitle: L10n.t("«تسجيل خروج» يزيل الجهاز من حسابه", "«Sign out» removes the device from the account"))
                ForEach(devices ?? []) { device in
                    AdminRowDivider(inset: AdminRowDivider.iconInset)
                    AdminMemberDeviceRow(device: device, canSignOut: true,
                                         busy: busy == AdminMemberConfirm.signOut(device).id) { ask(.signOut(device)) }
                }
            }
        case .suspend:
            AdminMemberTapRow(hint: frozen ? L10n.t("يسأل قبل رفع الإيقاف", "Asks before lifting")
                                           : L10n.t("يسأل قبل الإيقاف", "Asks before suspending"),
                              action: { ask(frozen ? .unsuspend : .suspend) }) {
                AdminMemberRow(icon: frozen ? "play.fill" : "pause.fill", tint: DS.Color.slate,
                               title: frozen ? L10n.t("رفع الإيقاف", "Lift the suspension")
                                             : L10n.t("إيقاف الحساب", "Suspend account"),
                               subtitle: frozen ? L10n.t("الحساب موقوف الآن", "The account is suspended")
                                                : L10n.t("يسأل قبل الإيقاف، والسبب اختياري", "Asks first; the reason is optional"),
                               showsChevron: true,
                               busy: busy == AdminMemberConfirm.suspend.id || busy == AdminMemberConfirm.unsuspend.id)
            }
        case .ban:
            if let banPrefill {
                AdminMemberTapRow(hint: L10n.t("يفتح «التسجيل والمنع» برقمه", "Opens sign-up and blocking with this number"),
                                  action: { openBans(banPrefill) }) {
                    AdminMemberRow(icon: "lock.fill", tint: DS.Color.slate,
                                   title: L10n.t("منع الرقم من التسجيل", "Block the number from signing up"),
                                   subtitle: ban == nil ? L10n.t("يفتح «التسجيل والمنع» برقمه", "Opens sign-up and blocking with this number")
                                                        : L10n.t("الرقم ممنوع من التسجيل الآن", "The number is blocked now"),
                                   showsChevron: true)
                }
            }
        case .delete:
            // آخر البطاقة بالأحمر، ويسأل قبل الحذف (spec A.6/A.14)
            AdminMemberTapRow(hint: L10n.t("يسأل قبل الحذف", "Asks before deleting"), action: { ask(.delete) }) {
                AdminMemberRow(icon: "trash", title: L10n.t("حذف العضو نهائياً", "Delete member permanently"),
                               subtitle: L10n.t("لا يمكن التراجع", "This can't be undone"),
                               destructive: true, busy: busy == AdminMemberConfirm.delete.id)
            }
            .disabled(busy == AdminMemberConfirm.delete.id)
        }
    }
}
