import SwiftUI
import Supabase

// MARK: - إعلان الوفاة (طلب المالك ٢٠٢٦-٠٩-٢٧؛ منذ الدفعة ب ٢٠٢٦-١٠-٢٠ بيته «المناسبات والإعلانات» ← «القادم»/«إنشاء»)
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
    /// تاريخ الوفاة «yyyy-MM-dd» إن عُرف — القديم (أكثر من ٣٠ يوماً) لا يُعرض له إعلان
    var deathDate: String? = nil
}

/// الوفيات «الحديثة» فقط تُعلَن (طلب المالك: «أي شخص متوفي سابقاً لا تظهره»)
enum DeathRecency {
    static var days: Int { RemoteSettings.int("death_announce_window_days", 30, range: 7...90) }
    /// تنبيه «وفاة لم يُعلن عنها» في اللوحة ٧ أيام فقط (طلب المالك ٢٠٢٦-١٠-٢١ «مابي اعلن عنه خلاص انتهى الوقت») —
    /// الإعلان نفسه يبقى ممكناً ٣٠ يوماً من صفحة العضو ومن «إنشاء»
    static var alertDays: Int {
        let days = UserDefaults.standard.integer(forKey: "server.deathAlertDays")
        return (1...30).contains(days) ? days : 7
    }

    /// تاريخ وفاة خلال آخر `within` يوماً (افتراضياً ٣٠، ولا في المستقبل)
    static func isRecent(_ deathDate: String?, within: Int = days) -> Bool {
        guard let raw = deathDate?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.count >= 10 else { return false }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: String(raw.prefix(10))) else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        guard let earliest = Calendar.current.date(byAdding: .day, value: -within, to: today) else { return false }
        return date >= earliest && date <= Date()
    }

    /// المربّع الآلي عند تسجيل الوفاة: بلا تاريخ = يظهر (الإداري يختار)، وبتاريخ قديم = لا
    static func allowsOffer(_ deathDate: String?) -> Bool {
        guard let raw = deathDate?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return true }
        return isRecent(raw)
    }

    static func string(from date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
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
        // وفاة قديمة (تصحيح بيانات) — لا إعلان
        guard canAnnounce, window == nil, DeathRecency.allowsOffer(target.deathDate) else { return }
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

    /// فتح يدوي (زر «إعلان وفاة» في صفحة المتوفى أو لوحة الإدارة) — النشر نفسه يرفض المكرر
    static func open(_ target: DeathAnnouncementTarget) {
        guard window == nil else { return }
        present(target)
    }

    /// المتوفون الذين أُعلن عنهم — فارغة إن تعذّر الجلب
    static func announcedIDs() async -> Set<UUID> {
        struct Row: Decodable { let member_id: UUID }
        let rows: [Row] = (try? await SupabaseConfig.client
            .from("death_announcements")
            .select("member_id")
            .execute()
            .value) ?? []
        return Set(rows.map(\.member_id))
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
        // نافذة مستقلّة لا تصلها بيئة التطبيق — لون القسم المختار (أزرار الإجراء)
        .dsSection(AppSection.current)
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
    /// «ماذا تنشئ؟» والمتوفى المختار أعلى المربّع (من المنشئ الواحد «إنشاء») — nil = المربّع وحده (عند تسجيل الوفاة)
    var chooser: AnyView? = nil
    let onClose: () -> Void

    @State private var content: String
    @State private var burial = ""
    @State private var notifyAll = true
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var published = false

    init(target: DeathAnnouncementTarget, chooser: AnyView? = nil, onClose: @escaping () -> Void) {
        self.target = target
        self.chooser = chooser
        self.onClose = onClose
        _content = State(initialValue: Self.defaultText(for: target))
    }

    /// النص الجاهز — بصيغة المذكّر أو المؤنث
    static func defaultText(for target: DeathAnnouncementTarget) -> String {
        let fallback = target.isFemale
            ? "انتقلت إلى رحمة الله تعالى \(target.name)\nتغمّدها الله بواسع رحمته وأسكنها فسيح جناته\nإنا لله وإنا إليه راجعون"
            : "انتقل إلى رحمة الله تعالى \(target.name)\nتغمّده الله بواسع رحمته وأسكنه فسيح جناته\nإنا لله وإنا إليه راجعون"
        return RemoteSettings.template(target.isFemale ? "death_announce_template_female" : "death_announce_template_male",
                                       fallback: fallback, name: target.name)
    }

    /// إطار المربّع بلون القسم (طلب المالك ٢٠٢٦-١٠-٠٥ «ابى مربع المتوفي يدخل بالألوان»):
    /// DSComposer يحوّل actionNavy إلى تعبئة القسم. الرمادي يبقى لون معنى «وفاة» في الشارات فقط.
    private var tint: Color { DS.Color.actionNavy }

    var body: some View {
        DSComposer(
            title: published ? L10n.t("تم نشر الإعلان", "Announcement Published")
                             : (chooser == nil ? L10n.t("إعلان وفاة", "Death Announcement") : L10n.t("ماذا تنشئ؟", "What to create?")),
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
                if let chooser { chooser }
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
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("إرسال إشعار لكل الأعضاء", "Notify all members"))
                        .dsFont(.rowTitle)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("يوصلهم تنبيه على الجوال", "They get an alert on their phone"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $notifyAll)
                    .labelsHidden()
                    .accessibilityLabel(L10n.t("إرسال إشعار لكل الأعضاء", "Notify all members"))
            }
            .dsRowBox()
        }

        if let errorText {
            DSNoteCard(errorText, icon: "exclamationmark.circle.fill", tint: DS.Color.error)
                .transition(.opacity)
        }
    }

    private var publishedSection: some View {
        DSComposerSection(title: L10n.t("تم", "Done"), icon: "checkmark", tint: tint, index: 0) {
            Text(notifyAll
                 ? L10n.t("نُشر الإعلان في الأخبار ووصل الإشعار لكل الأعضاء.",
                          "The announcement is in the news and all members were notified.")
                 : L10n.t("نُشر الإعلان في الأخبار.", "The announcement is in the news."))
                .dsFont(.bodyCompact)
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
                NotificationCenter.default.post(name: .deathAnnouncementPublished, object: target.id)
                await RealtimeManager.shared.newsVM?.fetchNews(force: true)
                isBusy = false
                // تأكيد هادئ يليق بالوفاة: قسم «تم» كما كان + اهتزاز خفيف — بلا لحظة احتفال (الدفعة ١٠)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
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
        // السيرفر يرفض إعلان وفاة قديمة (أكثر من ٣٠ يوماً) — 20261007130000
        if text.contains("death_not_recent") || ((error as? PostgrestError)?.hint ?? "") == "death_not_recent" {
            return L10n.t("لا يمكن إعلان وفاة قديمة — الإعلان متاح خلال ٣٠ يوماً من الوفاة.",
                          "Old deaths can't be announced — announcements are allowed within 30 days.")
        }
        return L10n.t("تعذّر النشر — تأكّد من الاتصال وحاول مرة ثانية.",
                      "Couldn't publish — check your connection and try again.")
    }
}

extension Notification.Name {
    /// نُشر إعلان وفاة — تحدّث القوائم التي تعرض «أُعلن عنهم»
    static let deathAnnouncementPublished = Notification.Name("deathAnnouncementPublished")
}
