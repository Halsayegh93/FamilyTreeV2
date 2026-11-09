import SwiftUI

/// «ما الجديد ونص الشاشة» (من «فرض التحديث»، مقترح samples/force-update): «ما الجديد» سطر لكل نقطة — يطلع في مربّع
/// التحديث وفي شاشة الإجبار — وعنوان شاشة الإجبار ورسالتها، ونص إشعار «ذكّرهم بإشعار». «معاينة» تعرضها مثل ما يشوفها
/// العضو. الحفظ للمالك عبر `set_update_policy` (فارغ = النص الافتراضي من السيرفر).
struct AdminUpdateWhatsNewView: View {
    @ObservedObject private var store = AdminUpdatePolicyStore.shared

    @State private var whatsNew = ""
    @State private var forceTitle = ""
    @State private var forceMessage = ""
    @State private var reminderTitle = ""
    @State private var reminderBody = ""
    @State private var loaded = false
    @State private var preview: PreviewItem?
    @State private var alertText: String?
    @State private var savedMoment = false

    private struct PreviewItem: Identifiable { let id = UUID() }

    private var policy: AdminUpdatePolicy? { store.policy }

    private var lines: [String] {
        whatsNew.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var dirty: Bool {
        guard let p = policy else { return false }
        return lines.joined(separator: "\n") != p.whatsNew || trimmed(forceTitle) != p.forceTitle
            || trimmed(forceMessage) != p.forceMessage || trimmed(reminderTitle) != p.reminderTitle
            || trimmed(reminderBody) != p.reminderBody
    }

    var body: some View {
        AdminPage(header: header, content: content)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .onAppear { adoptIfNeeded() }
            .task {
                if policy == nil { await store.load() }
                adoptIfNeeded()
            }
            .dsHalfBox(item: $preview) { _ in
                AnyView(AdminUpdatePreview(lines: lines,
                                           latestBuild: policy?.ios.latestBuild ?? 0,
                                           latestVersion: policy?.ios.latestVersion ?? "",
                                           forceTitle: trimmed(forceTitle).isEmpty ? L10n.t("حدّث التطبيق", "Update the App") : trimmed(forceTitle),
                                           forceMessage: trimmed(forceMessage)))
            }
            .dsAlert(L10n.t("لم يُحفظ", "Not saved"),
                     isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(alertText ?? "")
            }
            .dsAlert(L10n.t("تم الحفظ", "Saved"), isPresented: $savedMoment, moment: .success) {
                Button(L10n.t("حسناً", "OK")) {}
            }
    }

    private func adoptIfNeeded() {
        guard !loaded, let p = policy else { return }
        whatsNew = p.whatsNew
        forceTitle = p.forceTitle
        forceMessage = p.forceMessage
        reminderTitle = p.reminderTitle
        reminderBody = p.reminderBody
        loaded = true
    }

    private var versionLine: String {
        guard let ios = policy?.ios, ios.latestBuild > 0 else { return L10n.t("النسخة الجديدة", "New version") }
        return ios.latestVersion.isEmpty ? L10n.t("النسخة \(ios.latestBuild)", "Build \(ios.latestBuild)")
                                         : L10n.t("النسخة \(ios.latestVersion) — \(ios.latestBuild)",
                                                  "Version \(ios.latestVersion) — \(ios.latestBuild)")
    }

    private var header: AdminPageHeader {
        AdminPageHeader(title: L10n.t("ما الجديد", "What's new"),
                        subtitle: versionLine,
                        glyph: "text.badge.star",
                        kpis: [AdminPageKPI("\(lines.count)", L10n.t("نقطة", "points"), icon: "list.bullet")])
    }

    private var content: AnyView {
        guard policy != nil else {
            if case .failed(let msg) = store.phase {
                return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر التحميل", "Couldn't load"), message: msg,
                                                         retry: { Task { await store.load(); adoptIfNeeded() } })))
            }
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…"))))
        }
        return AnyView(VStack(spacing: DS.Hub.stackSpacing) {
            AdminSectionCard(title: L10n.t("ما الجديد (سطر لكل نقطة)", "What's new (one line per point)"),
                             tag: "\(whatsNew.count)/1200") {
                field(L10n.t("إضافة الأبناء مباشرة من «الأسرة»", "Add sons right from “My family”"),
                      text: $whatsNew, lines: 4...12, limit: 1200)
            }
            AdminSectionCard(title: L10n.t("شاشة الإجبار", "Lock screen")) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    label(L10n.t("العنوان", "Title"))
                    field(L10n.t("حدّث التطبيق", "Update the App"), text: $forceTitle, lines: 1...1, limit: 60)
                    label(L10n.t("الرسالة", "Message"))
                    field(L10n.t("نسخة التطبيق قديمة. يرجى التحديث من المتجر للمتابعة…", "Your version is out of date…"),
                          text: $forceMessage, lines: 2...5, limit: 400)
                }
            }
            AdminSectionCard(title: L10n.t("إشعار «ذكّرهم»", "“Remind them” notification"),
                             tag: L10n.t("من «النسخ عند الأعضاء»", "From “Versions”")) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    label(L10n.t("العنوان", "Title"))
                    field(L10n.t("يتوفر تحديث جديد للتطبيق", "A new app update"), text: $reminderTitle, lines: 1...1, limit: 80)
                    label(L10n.t("النص", "Text"))
                    field(L10n.t("نسختك قديمة. حدّث من المتجر…", "Your version is old…"), text: $reminderBody, lines: 2...4, limit: 300)
                }
            }
            Text(L10n.t("الحقل الفاضي = النص الافتراضي.", "An empty field = the default text."))
                .dsFont(.footnote)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Spacing.xs)
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("معاينة", "Preview"), icon: "eye", role: .cancel, size: .large) { preview = PreviewItem() }
                DSButton(L10n.t("حفظ", "Save"), icon: "checkmark", size: .large, isLoading: store.isSaving) { save() }
                    .disabled(!dirty || store.isSaving)
            }
        })
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .dsFieldFont(.label)
            .foregroundColor(DS.Color.fieldLabel)
    }

    private func field(_ placeholder: String, text: Binding<String>, lines: ClosedRange<Int>, limit: Int) -> some View {
        TextField(placeholder, text: Binding(get: { text.wrappedValue },
                                             set: { text.wrappedValue = String($0.prefix(limit)) }),
                  axis: .vertical)
            .dsFieldFont(.bodyCompact)
            .foregroundColor(DS.Color.textPrimary)
            .lineLimit(lines)
            .dsRowBox()
    }

    private func save() {
        var patch = AdminUpdatePolicyPatch()
        patch.whats_new = lines.joined(separator: "\n")
        patch.force_title = trimmed(forceTitle)
        patch.force_message = trimmed(forceMessage)
        patch.reminder_title = trimmed(reminderTitle)
        patch.reminder_body = trimmed(reminderBody)
        Task {
            if let err = await store.save(patch) {
                alertText = err
            } else {
                loaded = false
                adoptIfNeeded()
                savedMoment = true
            }
        }
    }
}

/// المعاينة: المربّع أو شاشة الإجبار كما يشوفها العضو
private struct AdminUpdatePreview: View {
    let lines: [String]
    let latestBuild: Int
    let latestVersion: String
    let forceTitle: String
    let forceMessage: String
    @State private var tab = 0

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            DSSegmentedSwitch(options: [
                DSSegmentOption(id: 0, title: L10n.t("المربّع", "Box"), icon: "sparkles"),
                DSSegmentOption(id: 1, title: L10n.t("شاشة الإجبار", "Lock screen"), icon: "lock.fill")
            ], selection: $tab, size: .regular)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)

            if tab == 0 {
                AppUpdateSheet(policy: samplePolicy, serverNow: Date(), storeURL: nil, onLater: {})
            } else {
                ForceUpdateContent(title: forceTitle,
                                   message: forceMessage.isEmpty
                                       ? L10n.t("هذه النسخة قديمة. يرجى التحديث من المتجر لمواصلة استخدام تطبيق عائلة المحمدعلي.",
                                                "Your version is out of date. Update from the store to keep using the app.")
                                       : forceMessage,
                                   lines: lines, onOpenStore: {})
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, DS.Spacing.lg)
            }
        }
    }

    private var samplePolicy: AppUpdatePolicy {
        AppUpdatePolicy(state: .optional, reason: nil, exempt: false, canSnooze: true, latestBuild: latestBuild,
                        latestVersion: latestVersion,
                        minBuild: 0, deadline: nil, updateURL: nil, snoozeDays: 2, whatsNew: lines,
                        forceTitle: nil, forceMessage: nil, serverNow: nil)
    }
}
