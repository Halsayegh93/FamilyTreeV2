import SwiftUI
import Supabase

// MARK: - إعلان الوفاة (طلب المالك ٢٠٢٦-٠٩-٢٧)
//
// عند تسجيل وفاة عضو (قبول طلب وفاة، أو تسجيلها من الإدارة مباشرة، أو في شجرة النساء)
// يطلع للإداري مربّع «إعلان وفاة» بنص جاهز قابل للتعديل + موعد الدفن ومكانه (اختياري).
// «نشر الإعلان» يستدعي دالة السيرفر `announce_death`: منشور «وفاة» في الأخبار باسم
// «إدارة العائلة» (تبرزه الرئيسية ٣٠ يوماً) + إشعار لكل الأعضاء — مرة واحدة لكل شخص.
// «ليس الآن» للوفيات القديمة وتصحيح البيانات: لا يُعلَن شيء تلقائياً أبداً.

struct DeathAnnouncementTarget: Identifiable, Equatable {
    /// profiles.id أو women_members.id
    let id: UUID
    let name: String
    let isFemale: Bool
}

/// يعرض المربّع في نافذة فوق كل شيء — الوفاة تُسجَّل من أوراق ومربّعات مختلفة
/// (وقد تُغلق قبل انتهاء الحفظ)، فلا يرتبط العرض بشاشة معيّنة
@MainActor
enum DeathAnnouncementPresenter {
    private static var window: UIWindow?
    private static weak var previousKey: UIWindow?

    /// يعرض المربّع لمن يملك الصلاحية وإن لم يُعلَن عن هذا الشخص من قبل.
    /// إن لم تُطبَّق دالة السيرفر بعد (الجدول غير موجود) لا يظهر شيء.
    static func offer(_ target: DeathAnnouncementTarget, canAnnounce: Bool) async {
        guard canAnnounce, window == nil else { return }
        struct Row: Decodable { let member_id: UUID }
        do {
            let rows: [Row] = try await SupabaseConfig.client
                .from("death_announcements")
                .select("member_id")
                .eq("member_id", value: target.id.uuidString)
                .limit(1)
                .execute()
                .value
            guard rows.isEmpty else { return }
        } catch {
            Log.warning("[DeathAnnouncement] لا يُعرض المربّع — تعذّر التحقق: \(error.localizedDescription)")
            return
        }
        // بعد أن تُغلق الورقة/المربّع الذي سُجّلت منه الوفاة
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard window == nil else { return }
        present(target)
    }

    private static func present(_ target: DeathAnnouncementTarget) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        previousKey = scene.windows.first(where: \.isKeyWindow)
        let root = DSCenterPanel(onBackgroundTap: nil, hugsContent: true) {
            DeathAnnouncementBox(target: target, onClose: { close() })
        }
        .environment(\.locale, LanguageManager.shared.locale)
        let host = UIHostingController(rootView: root)
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        // تحت نافذة التنبيهات (.alert + 1) فيظهر أي تنبيه فوقه
        w.windowLevel = .alert
        w.backgroundColor = .clear
        w.overrideUserInterfaceStyle = DSPopupPresenter.appInterfaceStyle(in: scene)
        w.rootViewController = host
        w.makeKeyAndVisible()
        window = w
    }

    static func close() {
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: 0.2, animations: { w.alpha = 0 }, completion: { _ in
            w.isHidden = true
            w.rootViewController = nil
            previousKey?.makeKey()
        })
    }
}

struct DeathAnnouncementBox: View {
    let target: DeathAnnouncementTarget
    let onClose: () -> Void

    @State private var content: String
    @State private var burial = ""
    @State private var notifyAll = true
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var published = false

    init(target: DeathAnnouncementTarget, onClose: @escaping () -> Void) {
        self.target = target
        self.onClose = onClose
        _content = State(initialValue: Self.defaultText(for: target))
    }

    /// النص الجاهز — بصيغة المذكّر أو المؤنث
    static func defaultText(for target: DeathAnnouncementTarget) -> String {
        target.isFemale
            ? "انتقلت إلى رحمة الله تعالى \(target.name)\nتغمّدها الله بواسع رحمته وأسكنها فسيح جناته\nإنا لله وإنا إليه راجعون"
            : "انتقل إلى رحمة الله تعالى \(target.name)\nتغمّده الله بواسع رحمته وأسكنه فسيح جناته\nإنا لله وإنا إليه راجعون"
    }

    private var tint: Color { NewsTypeHelper.color(for: "وفاة") }

    var body: some View {
        DSComposer(
            title: published ? L10n.t("تم نشر الإعلان", "Announcement Published")
                             : L10n.t("إعلان وفاة", "Death Announcement"),
            subtitle: target.name,
            icon: published ? "checkmark" : NewsTypeHelper.icon(for: "وفاة"),
            tint: tint,
            actionTitle: L10n.t("نشر الإعلان", "Publish"),
            actionIcon: "paperplane.fill",
            showsAction: !published,
            cancelTitle: published ? L10n.t("إغلاق", "Close") : L10n.t("ليس الآن", "Not Now"),
            canSubmit: !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            isBusy: isBusy,
            note: published ? nil : L10n.t("يُنشر في الأخبار باسم «إدارة العائلة» — مرة واحدة فقط",
                                           "Posted in the news as the family administration — once only"),
            onSubmit: publish,
            onCancel: onClose
        ) {
            if published {
                publishedSection
            } else {
                formSections
            }
        }
    }

    @ViewBuilder private var formSections: some View {
        DSComposerSection(title: L10n.t("نص الإعلان", "Announcement"),
                          icon: "text.quote", tint: tint, index: 0) {
            DSComposerField(icon: "text.alignright",
                            label: L10n.t("النص", "Text"),
                            placeholder: L10n.t("نص الإعلان", "Announcement text"),
                            text: $content, tint: tint, multiline: true, limit: 600)
        }

        DSComposerSection(title: L10n.t("الدفن", "Burial"),
                          icon: "clock.fill", tint: tint,
                          trailing: L10n.t("اختياري", "Optional"), index: 1) {
            DSComposerField(icon: "mappin.and.ellipse",
                            label: L10n.t("موعد الدفن ومكانه", "Burial time and place"),
                            placeholder: L10n.t("مثال: بعد صلاة العصر — مقبرة الصليبيخات",
                                                "e.g. after Asr prayer — Sulaibikhat cemetery"),
                            text: $burial, tint: tint, limit: 160)
        }

        DSComposerSection(title: L10n.t("الإشعار", "Notification"),
                          icon: "bell.fill", tint: tint, index: 2) {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "bell.badge.fill", tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("إرسال إشعار لكل الأعضاء", "Notify all members"))
                        .font(DS.Font.plex(13.5, weight: .bold))
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("يوصلهم تنبيه على الجوال", "They get an alert on their phone"))
                        .font(DS.Font.plex(11))
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $notifyAll)
                    .labelsHidden()
                    .tint(DS.Color.primary)
                    .accessibilityLabel(L10n.t("إرسال إشعار لكل الأعضاء", "Notify all members"))
            }
            .dsRowBox()
        }

        if let errorText {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(errorText)
                    .font(DS.Font.plex(12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(DS.Color.error)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    private var publishedSection: some View {
        DSComposerSection(title: L10n.t("تم", "Done"), icon: "checkmark", tint: tint, index: 0) {
            Text(notifyAll
                 ? L10n.t("نُشر الإعلان في الأخبار ووصل الإشعار لكل الأعضاء.",
                          "The announcement is in the news and all members were notified.")
                 : L10n.t("نُشر الإعلان في الأخبار.", "The announcement is in the news."))
                .font(DS.Font.plex(13.5))
                .foregroundColor(DS.Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func publish() {
        guard !isBusy else { return }
        guard NetworkMonitor.shared.requireOnline() else { return }
        struct Params: Encodable {
            let p_member_id: String
            let p_content: String
            let p_burial: String?
            let p_notify: Bool
        }
        let trimmedBurial = burial.trimmingCharacters(in: .whitespacesAndNewlines)
        let params = Params(p_member_id: target.id.uuidString,
                            p_content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                            p_burial: trimmedBurial.isEmpty ? nil : trimmedBurial,
                            p_notify: notifyAll)
        isBusy = true
        errorText = nil
        Task {
            do {
                try await SupabaseConfig.client.rpc("announce_death", params: params).execute()
                Log.info("[DeathAnnouncement] نُشر إعلان وفاة: \(target.name)")
                await RealtimeManager.shared.newsVM?.fetchNews(force: true)
                isBusy = false
                withAnimation(DSMotion.fade) { published = true }
            } catch {
                Log.error("[DeathAnnouncement] فشل النشر: \(error.localizedDescription)")
                isBusy = false
                withAnimation(DSMotion.fade) { errorText = Self.message(for: error) }
            }
        }
    }

    private static func message(for error: Error) -> String {
        let code = (error as? PostgrestError)?.code ?? ""
        let text = error.localizedDescription
        if code == "23505" || text.contains("already announced") {
            return L10n.t("تم الإعلان عن هذه الوفاة من قبل.", "This death was already announced.")
        }
        if code == "42501" {
            return L10n.t("ما عندك صلاحية نشر إعلان الوفاة.", "You can't publish death announcements.")
        }
        if code == "22023" {
            return L10n.t("العضو غير مسجّل كمتوفى.", "The member isn't marked as deceased.")
        }
        return L10n.t("تعذّر النشر — تأكّد من الاتصال وحاول مرة ثانية.",
                      "Couldn't publish — check your connection and try again.")
    }
}
