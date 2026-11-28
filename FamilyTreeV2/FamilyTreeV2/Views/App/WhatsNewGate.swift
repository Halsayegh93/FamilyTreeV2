import SwiftUI
import Combine

// MARK: - «ما الجديد» بعد التحديث (القرار ٨، موافقة المالك ٢٠٢٦-١١-١٢ «ممتاز»)
//
// مربّع يظهر مرة واحدة لكل نسخة (رقم البناء) للعضو الموجود — لا للمسجّل الجديد (انضمّ قبل أقل من يومين) — بعد فحص
// الإشعارات ومربّعه، وقبل «كمّل ملفك بصورة». النقاط من السيرفر إن وُجدت (`app_config.whats_new_screen`: نص JSON
// `[{"icon","title","text","tint"}]`، و`[]` = لا يظهر — قاعدة «الأرقام والنصوص على السيرفر»)، وإلا النص المعتمد هنا.

@MainActor
final class WhatsNewStore: ObservableObject {
    static let shared = WhatsNewStore()

    /// المربّع معروض الآن — «كمّل ملفك بصورة» ينتظره
    @Published var showing = false

    private static let seenKey = "whatsNew.seenBuild"
    static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "" }
    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "" }

    struct Item: Decodable, Identifiable {
        let icon: String
        let title: String
        let text: String
        var tint: String? = nil
        var id: String { title }
    }

    /// يظهر؟ نسخة لم يُعرض لها، وفيه نقاط، والعضو انضمّ قبل يومين على الأقل
    func shouldShow(memberCreatedAt: String?) -> Bool {
        guard UserDefaults.standard.string(forKey: Self.seenKey) != Self.build else { return false }
        guard !items.isEmpty else { markSeen(); return false }
        // تاريخ الانضمام بصيغة السيرفر الكاملة (بأجزاء الثانية) — اليوم وحده يكفي؛ غير معروف = عضو موجود
        if let raw = memberCreatedAt, raw.count >= 10,
           let joined = DateHelper.parse(String(raw.prefix(10))),
           Date().timeIntervalSince(joined) < 2 * 24 * 3600 {
            markSeen()   // المسجّل الجديد: لا «ما الجديد» لهذه النسخة
            return false
        }
        return true
    }

    func markSeen() { UserDefaults.standard.set(Self.build, forKey: Self.seenKey) }

    /// نقاط السيرفر إن وُجدت، وإلا المعتمدة
    var items: [Item] {
        if let raw = AppConfigValues.shared.string("whats_new_screen"),
           let data = raw.data(using: .utf8),
           let list = try? JSONDecoder().decode([Item].self, from: data) {
            return list
        }
        return Self.defaults
    }

    static var defaults: [Item] {
        [Item(icon: "gearshape.fill", title: L10n.t("إعدادات أوضح", "Clearer settings"),
              text: L10n.t("الإعدادات مرتّبة في مجموعات، وصورتك واسمك أعلاها.",
                           "Settings are grouped, with your photo and name on top."), tint: "navy"),
         Item(icon: "lock.fill", title: L10n.t("خصوصية أبسط", "Simpler privacy"),
              text: L10n.t("مفتاح واحد لكل معلومة: الرقم، الصورة، الميلاد، آخر ظهور.",
                           "One switch per detail: phone, photo, birth date, last seen."), tint: "palm"),
         Item(icon: "folder.fill", title: L10n.t("مجلدات في المكتبة", "Library folders"),
              text: L10n.t("ملفات العائلة مرتّبة في مجلدات.", "Family files are organized in folders."), tint: "sea"),
         Item(icon: "wand.and.stars", title: L10n.t("تحسينات وإصلاحات", "Improvements and fixes"),
              text: L10n.t("تصميم موحّد في كل الشاشات، وإصلاح أخطاء صغيرة.",
                           "One design across all screens, and small fixes."), tint: "gold")]
    }

    /// لون مربّع الرمز من اسمه (عائلة الكحلي والذهبي)
    static func fill(_ name: String?) -> Color {
        switch name {
        case "palm": return DS.Color.palmFill
        case "sadu": return DS.Color.saduFill
        case "sea":  return DS.Color.seaFill
        case "gold": return DS.Color.goldFill
        case "slate": return DS.Color.slateFill
        default:     return DS.Color.navyFill
        }
    }
}

/// يعرض «ما الجديد» مرة واحدة حين يُرفع `blocked` (بعد الإشعارات ومربّعها)
struct WhatsNewGate: ViewModifier {
    let blocked: Bool
    @EnvironmentObject private var authVM: AuthViewModel
    @ObservedObject private var store = WhatsNewStore.shared

    func body(content: Content) -> some View {
        content
            .task(id: blocked) {
                guard !blocked else { return }
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                guard !Task.isCancelled,
                      store.shouldShow(memberCreatedAt: authVM.currentUser?.createdAt) else { return }
                store.showing = true
            }
            .dsCenterBox(isPresented: $store.showing) {
                WhatsNewBox(items: store.items) {
                    store.markSeen()
                    store.showing = false
                }
                .onDisappear { store.markSeen() }
            }
    }
}

/// المربّع: «ما الجديد» + النسخة، صفّ لكل نقطة (مربّع رمز ملوّن · العنوان · سطر)، و«متابعة» وحده
struct WhatsNewBox: View {
    let items: [WhatsNewStore.Item]
    let onDone: () -> Void

    var body: some View {
        DSComposer(
            title: L10n.t("ما الجديد", "What's new"),
            subtitle: L10n.t("النسخة \(WhatsNewStore.version)", "Version \(WhatsNewStore.version)"),
            icon: "sparkles",
            tint: DS.Color.actionNavy,
            actionTitle: L10n.t("متابعة", "Continue"),
            actionIcon: "checkmark",
            showsCancel: false,
            canSubmit: true,
            actionFullRow: true,
            onSubmit: onDone,
            onCancel: onDone
        ) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().padding(.leading, DS.Icon.rowLarge + DS.Spacing.md) }
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Image(systemName: item.icon)
                            .dsGlyph(DS.Glyph.lg, weight: .semibold)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                            .background(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill(WhatsNewStore.fill(item.tint)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                            Text(item.title)
                                .dsFont(.rowTitle)
                                .foregroundColor(DS.Color.textPrimary)
                            Text(item.text)
                                .dsFont(.footnote)
                                .foregroundColor(DS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, DS.Spacing.sm)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
