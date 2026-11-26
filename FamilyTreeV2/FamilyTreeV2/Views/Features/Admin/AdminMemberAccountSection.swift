import SwiftUI

// MARK: - «الحساب» في ورقة العضو «أ3» (الوحدة V2-3) — قسم مستقل (حارس المكدس)
//
// شريط بترولي ثم بطاقة: الهاتف (كما يعيده السيرفر، مخفياً لمن لا يراه) · «تسجيل في التطبيق» (حبّة «مسجّل ✓» أو «سجّل»
// بتأكيد) · آخر دخول (وتحته استخدامه للتطبيق) · الأجهزة (العدد ⌄ — تنفتح تحته بـ«تسجيل خروج» لكل جهاز، `canManageDevices`)
// · «إيقاف الحساب» ‹ (`canFreezeMembers`) · «منع الرقم من التسجيل» ‹ (`canManageBannedPhones` — يفتح «التسجيل والمنع» برقمه).
// للأحياء كلهم كما كان: «تسجيل في التطبيق» وتعديل الرقم بيتهما هنا (العضو بلا حساب يُسجَّل من هذا القسم).
// الإيقاف والمنع لغيرك فقط (لا ورقتك ولا ورقة المالك — `AdminMemberSheetLogic.accountCommands`)، والحذف زرّ مستقل آخر الورقة.
// كل فعل يمرّ بالورقة (`ask` = التأكيد، `openBox` = المربّعات، `openBans` = الصفحة) — نفس النداءات السابقة.

struct AdminMemberAccountSection: View {
    let member: FamilyMember
    let facts: AdminMemberSheetFacts
    let canEdit: Bool
    let isOther: Bool
    let commands: AdminMemberSheetLogic.AccountCommands
    /// الرقم المطبَّع لصفحة «التسجيل والمنع» (nil = مخفي أو غير صالح)
    let banPrefill: String?
    let liveStatus: FamilyMember.MemberStatus?
    /// منع رقمه الساري (للعرض فقط)
    let ban: BannedPhone?
    let devices: [NotificationViewModel.LinkedDevice]?
    let devicesFailed: Bool
    @Binding var devicesOpen: Bool
    /// الأجهزة لمن له حساب دخول، وللمالك (`canViewSystemSettings`)
    let showsDevices: Bool
    let canSignOutDevices: Bool
    let busy: String?
    let openBox: (AdminMemberBox) -> Void
    let ask: (AdminMemberConfirm) -> Void
    let openBans: (String) -> Void
    let retryDevices: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var phone: String { (member.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
    private var frozen: Bool { facts.status == .frozen }

    var body: some View {
        AdminMemberSheetSection(title: L10n.t("الحساب", "Account"), bar: DS.Color.sea) {
            phoneRow
            registerRow
            AdminMemberRow(icon: "clock.fill", tint: DS.Color.sea, title: L10n.t("آخر دخول", "Last sign-in"),
                           subtitle: facts.usageLine, value: facts.lastSeenText)
            // الأجهزة لمن له حساب دخول (من بلا حساب لا جهاز له)
            if showsDevices {
                devicesRow
                if devicesOpen, let devices, !devicesFailed {
                    ForEach(devices) { device in deviceRow(device) }
                }
            }
            if commands.suspend {
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
            }
            if commands.ban, let banPrefill {
                AdminMemberTapRow(hint: L10n.t("يفتح «التسجيل والمنع» برقمه", "Opens sign-up and blocking with this number"),
                                  action: { openBans(banPrefill) }) {
                    AdminMemberRow(icon: "lock.fill", tint: DS.Color.slate,
                                   title: L10n.t("منع الرقم من التسجيل", "Block the number from signing up"),
                                   subtitle: ban == nil ? L10n.t("يفتح «التسجيل والمنع» برقمه", "Opens sign-up and blocking with this number")
                                                        : L10n.t("الرقم ممنوع من التسجيل الآن", "The number is blocked now"),
                                   showsChevron: true)
                }
            }
        }
    }

    // MARK: الصفوف

    /// الرقم كما وصل من السيرفر (مخفياً لمن لا يراه) — يُعدَّل بمربّع الرقم لمن يعدّل
    @ViewBuilder
    private var phoneRow: some View {
        let row = AdminMemberRow(icon: "phone.fill", tint: DS.Color.sea, title: L10n.t("الهاتف", "Phone"),
                                 value: phone.isEmpty ? L10n.t("بلا رقم هاتف", "No phone") : KuwaitPhone.display(phone),
                                 valueIsNumber: !phone.isEmpty, showsChevron: canEdit)
        if canEdit {
            AdminMemberTapRow(hint: phone.isEmpty ? L10n.t("إضافة", "Add") : L10n.t("تعديل", "Edit"),
                              action: { openBox(.phone(member)) }) { row }
        } else {
            row
        }
    }

    /// «تسجيل في التطبيق»: حبّة الحالة، أو حبّة «سجّل» حين يمكن (بتأكيد) — نفس شرط الزرّ السابق
    private var registerRow: some View {
        let canRegister = canEdit && isOther && !frozen && !phone.isEmpty && member.role != .pending
            && (liveStatus ?? member.status) != .active && facts.status != .registered
        let note: String? = {
            guard !canRegister, facts.status == .treeOnly else { return nil }
            if phone.isEmpty { return L10n.t("يحتاج رقم هاتف أولاً", "Needs a phone number first") }
            return nil
        }()
        return AdminMemberRow(icon: "iphone", tint: DS.Color.sea, title: L10n.t("تسجيل في التطبيق", "Registered in the app"),
                              subtitle: note, busy: busy == AdminMemberConfirm.register.id) {
            if canRegister {
                AdminPillButton(title: L10n.t("سجّل", "Register"), style: .navy) { ask(.register) }
                    .accessibilityLabel(L10n.t("تسجيل في التطبيق", "Register in the app"))
                    .accessibilityHint(L10n.t("يسأل قبل التسجيل", "Asks first"))
            } else {
                AdminStatePill(title: Self.registerWord(facts.status), tone: Self.registerTone(facts.status),
                               icon: facts.status == .registered ? "checkmark" : nil)
            }
        }
    }

    private static func registerWord(_ status: AdminMemberStatus?) -> String {
        switch status {
        case .registered: return L10n.t("مسجّل", "Registered")
        case .frozen: return L10n.t("موقوف", "Suspended")
        case .pendingJoin: return L10n.t("قيد المراجعة", "Under review")
        case .treeOnly, .deceased: return L10n.t("غير مسجّل", "Not registered")
        case nil: return AdminStoreHealthText.placeholder
        }
    }

    private static func registerTone(_ status: AdminMemberStatus?) -> AdminPillTone {
        switch status {
        case .registered: return .ok
        case .frozen: return .error
        default: return .off
        }
    }

    /// «الأجهزة · 2 ⌄» يفتح أجهزته تحته (و«تسجيل خروج» للمالك) — التحميل «—»، والفشل «تعذّر التحميل» يعيد الجلب
    @ViewBuilder
    private var devicesRow: some View {
        let title = L10n.t("الأجهزة", "Devices")
        if let devices {
            if devicesFailed {
                AdminMemberTapRow(hint: AdminStoreHealthText.retry, action: retryDevices) {
                    AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title) {
                        AdminStatePill(title: AdminStoreHealthText.failed, tone: .unknown, icon: "arrow.clockwise")
                    }
                }
            } else if devices.isEmpty {
                AdminMemberRow(icon: "iphone.slash", tint: DS.Color.sea, title: title,
                               subtitle: L10n.t("لا تصله الإشعارات", "Gets no notifications"),
                               value: L10n.t("لا أجهزة", "None"))
            } else {
                AdminMemberTapRow(hint: devicesOpen ? L10n.t("يطوي الأجهزة", "Hides the devices")
                                                    : L10n.t("يعرض الأجهزة", "Shows the devices"),
                                  action: { withAnimation(reduceMotion ? nil : DS.Anim.snappy) { devicesOpen.toggle() } }) {
                    AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title,
                                   subtitle: canSignOutDevices && !devicesOpen
                                       ? L10n.t("افتحها لتسجيل خروج أي جهاز", "Open to sign out any device") : nil,
                                   value: "\(devices.count)", valueIsNumber: true) {
                        Image(systemName: "chevron.down")
                            .dsGlyph(DS.Glyph.sm)
                            .foregroundColor(DS.Color.textTertiary)
                            .rotationEffect(.degrees(devicesOpen ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityValue(devicesOpen ? L10n.t("ظاهرة", "Shown") : L10n.t("مطويّة", "Collapsed"))
            }
        } else {
            AdminMemberRow(icon: "iphone.gen3", tint: DS.Color.sea, title: title, value: AdminStoreHealthText.placeholder)
                .accessibilityValue(AdminStoreHealthText.loading)
        }
    }

    /// جهاز تحت «الأجهزة»: مزاح بعرض مربّع الأيقونة، الاسم و«آخر استخدام …»، و«تسجيل خروج» حمراء بإطار
    private func deviceRow(_ device: NotificationViewModel.LinkedDevice) -> some View {
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
            if busy == AdminMemberConfirm.signOut(device).id {
                ProgressView()
                    .scaleEffect(DS.Spinner.chipScale)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            } else if canSignOutDevices {
                AdminPillButton(title: L10n.t("تسجيل خروج", "Sign out"), style: .reject) { ask(.signOut(device)) }
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
