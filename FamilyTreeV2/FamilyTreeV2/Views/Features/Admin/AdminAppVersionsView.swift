import SwiftUI
import Supabase

/// «النسخ عند الأعضاء» (من «فرض التحديث»، مقترح samples/force-update): كم جهاز على آخر نسخة وكم على أقدم (آخر ٣٠
/// يوماً، لكل منصة)، وقائمة الأجهزة على نسخة قديمة (المنصة · النسخة · آخر ظهور)، و«ذكّرهم بإشعار» بنص السيرفر
/// (`update_reminder_title/body`) عبر مسار الإرسال الموجود (`sendNotification`، نوع `app_update` ← «المستجدات»).
/// الأجهزة تبلّغ نسختها بعد التسجيل (`report_app_build`)؛ ما لم يبلّغ = نسخة قبل هذه الميزة (أقدم). للمالك وحده
/// (`app_build_overview`).
struct AdminAppVersionsView: View {
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @ObservedObject private var policyStore = AdminUpdatePolicyStore.shared

    private enum Phase: Equatable { case loading, loaded, unavailable, failed(String) }

    @State private var phase: Phase = .loading
    @State private var overview: AdminBuildOverview?
    @State private var confirmRemind = false
    @State private var sending = false
    @State private var sentCount: Int?
    @State private var alertText: String?

    private static let days = 30

    var body: some View {
        AdminPage(header: header, content: content)
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            .task {
                await load()
                if policyStore.policy == nil { await policyStore.load() }
            }
            .refreshable { await load() }
            .dsAlert(L10n.t("ذكّرهم بإشعار؟", "Remind them?"), isPresented: $confirmRemind) {
                Button(L10n.t("أرسل", "Send")) { remind() }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.t("يوصل \(memberIds.count) عضو إشعار «\(reminderTitle)».",
                            "\(memberIds.count) members get “\(reminderTitle)”."))
            }
            .dsAlert(L10n.t("تم الإرسال", "Sent"),
                     isPresented: Binding(get: { sentCount != nil }, set: { if !$0 { sentCount = nil } }),
                     moment: .success) {
                Button(L10n.t("حسناً", "OK")) {}
            }
            .dsAlert(L10n.t("ما انرسل", "Not sent"),
                     isPresented: Binding(get: { alertText != nil }, set: { if !$0 { alertText = nil } })) {
                Button(L10n.t("حسناً", "OK")) {}
            } message: {
                Text(alertText ?? "")
            }
    }

    // MARK: - البيانات

    private func load() async {
        if overview == nil { phase = .loading }
        do {
            let o: AdminBuildOverview = try await SupabaseConfig.client
                .rpc("app_build_overview", params: ["p_days": Self.days]).execute().value
            overview = o
            phase = .loaded
        } catch {
            if ErrorHelper.isCancellation(error) { return }
            if AdminUpdatePolicyStore.isMissing(error) { phase = .unavailable; return }
            Log.warning("[UPDATE] تعذّر جلب النسخ عند الأعضاء: \(error.localizedDescription)")
            if overview == nil { phase = .failed(AdminUpdatePolicyStore.message(error)) }
        }
    }

    private var oldDevices: [AdminBuildOverview.Device] { overview?.devices ?? [] }

    /// كل عضو مرة واحدة
    private var memberIds: [UUID] {
        var seen = Set<UUID>()
        return oldDevices.compactMap { seen.insert($0.member_id).inserted ? $0.member_id : nil }
    }

    private var reminderTitle: String {
        let t = policyStore.policy?.reminderTitle.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? L10n.t("فيه تحديث جديد للتطبيق", "A new app update is available") : t
    }

    private var reminderBody: String {
        let t = policyStore.policy?.reminderBody.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? L10n.t("نسختك من التطبيق قديمة. حدّث من المتجر عشان توصلك آخر الإضافات.",
                                  "Your app version is old. Update from the store to get the latest.") : t
    }

    private func remind() {
        let ids = memberIds
        guard !ids.isEmpty, !sending else { return }
        sending = true
        Task {
            let ok = await notificationVM.sendNotification(title: reminderTitle, body: reminderBody,
                                                          targetMemberIds: ids, kind: "app_update")
            sending = false
            if ok { sentCount = ids.count } else {
                alertText = L10n.t("تعذّر إرسال الإشعار — تحقّق من الاتصال وجرّب مرة ثانية.",
                                   "Couldn't send — check the connection and retry.")
            }
        }
    }

    // MARK: - الرأس

    private var header: AdminPageHeader {
        let o = overview
        let total = (o?.ios.total ?? 0) + (o?.android.total ?? 0)
        let onLatest = (o?.ios.on_latest ?? 0) + (o?.android.on_latest ?? 0)
        return AdminPageHeader(
            title: L10n.t("النسخ عند الأعضاء", "Versions on devices"),
            subtitle: L10n.t("آخر \(Self.days) يوم", "Last \(Self.days) days"),
            glyph: "iphone.and.arrow.forward",
            kpis: [
                AdminPageKPI(AdminPageKPI.count(onLatest, ready: o != nil), L10n.t("على الأخيرة", "On latest"),
                             icon: "checkmark.seal.fill", ring: total > 0 ? Double(onLatest) / Double(total) : nil),
                AdminPageKPI(AdminPageKPI.count(oldDevices.count, ready: o != nil), L10n.t("أقدم", "Older"),
                             icon: "clock.arrow.circlepath", tint: oldDevices.isEmpty ? DS.Color.textOnPrimary : DS.Hub.kpiMine),
                AdminPageKPI(AdminPageKPI.count(total, ready: o != nil), L10n.t("جهاز", "Devices"), icon: "iphone.gen3")
            ])
    }

    // MARK: - المحتوى

    private var content: AnyView {
        switch phase {
        case .loading where overview == nil:
            return AnyView(AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…"))))
        case .unavailable:
            return AnyView(AdminPageStateCard(.empty(L10n.t("تحتاج تحديث السيرفر", "Needs a server update"),
                                                     message: L10n.t("الأجهزة ما تسجّل رقم نسختها قبل تطبيق ترحيل «فرض التحديث».",
                                                                     "Devices don't report their build until the server update is applied."))))
        case .failed(let msg) where overview == nil:
            return AnyView(AdminPageStateCard(.error(L10n.t("تعذّر التحميل", "Couldn't load"), message: msg,
                                                     retry: { Task { await load() } })))
        default:
            break
        }
        guard let o = overview else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: DS.Hub.stackSpacing) {
            AdaptiveCardStack(spacing: DS.Hub.stackSpacing, alignment: .leading) {
                AnyView(AdminBuildShareCard(title: L10n.t("الآيفون", "iPhone"), stats: o.ios))
                AnyView(AdminBuildShareCard(title: L10n.t("الأندرويد", "Android"), stats: o.android))
            }
            AnyView(oldList)
            if !memberIds.isEmpty {
                DSButton(L10n.t("ذكّرهم بإشعار", "Remind them"), icon: "bell", role: .cancel, size: .large,
                         isLoading: sending) { confirmRemind = true }
            }
        })
    }

    private var oldList: some View {
        AdminSectionCard(title: L10n.t("على نسخة قديمة", "On an old version"), badge: oldDevices.count,
                         badgeTint: DS.Color.warning) {
            if oldDevices.isEmpty {
                AdminInfoRow(icon: "checkmark.seal.fill", tint: DS.Color.success,
                             title: L10n.t("الكل على آخر نسخة", "Everyone is on the latest"))
            } else {
                AdminLazyRows(items: oldDevices) { d in AnyView(AdminOldDeviceRow(device: d)) }
            }
        }
    }
}

/// «على آخر نسخة — ٤١ من ٦٢ جهاز» + الشريط والمفتاح
private struct AdminBuildShareCard: View {
    let title: String
    let stats: AdminBuildOverview.Platform

    var body: some View {
        AdminSectionCard(title: title,
                         tag: stats.latest_build > 0 ? L10n.t("الأخيرة \(stats.latest_build)", "Latest \(stats.latest_build)") : nil) {
            if stats.total == 0 {
                Text(L10n.t("ما فيه أجهزة آخر ٣٠ يوم", "No devices in the last 30 days"))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
            } else {
                HStack {
                    Text(L10n.t("على آخر نسخة", "On the latest"))
                        .dsFont(.hubRow)
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer()
                    Text(L10n.t("\(stats.on_latest) من \(stats.total) جهاز", "\(stats.on_latest) of \(stats.total) devices"))
                        .dsFont(.chip)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.success)
                }
                DSMeterBar(parts: DSGaugePart.counts([
                    (id: "latest", value: stats.on_latest, tint: DS.Color.success),
                    (id: "older", value: stats.older, tint: DS.Color.warning),
                    (id: "unknown", value: stats.unknown, tint: DS.Color.error)
                ]))
                DSGaugeLegend(items: legend, columns: 3)
            }
        }
    }

    private var legend: [DSGaugeLegend.Item] {
        var items = [DSGaugeLegend.Item("latest", L10n.t("\(stats.latest_build) (الأخيرة)", "\(stats.latest_build) (latest)"),
                                        "\(stats.on_latest)", tint: DS.Color.success)]
        // أعلى نسخة أقدم بالاسم، والباقي «أقدم»
        let older = stats.builds.filter { $0.build < stats.latest_build }
        if let top = older.first {
            items.append(.init("b\(top.build)", "\(top.build)", "\(top.count)", tint: DS.Color.warning))
            let rest = older.dropFirst().reduce(0) { $0 + $1.count }
            if rest > 0 { items.append(.init("rest", L10n.t("أقدم", "Older"), "\(rest)", tint: DS.Color.warning)) }
        }
        if stats.unknown > 0 {
            items.append(.init("unknown", L10n.t("قبل التسجيل", "Unreported"), "\(stats.unknown)", tint: DS.Color.error))
        }
        return items
    }
}

/// صفّ جهاز قديم: الحرف الأول · الاسم · «آيفون · 49 · آخر ظهور أمس»
private struct AdminOldDeviceRow: View {
    let device: AdminBuildOverview.Device

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DSMemberAvatar(name: device.name, avatarUrl: nil, size: DS.Icon.rowLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(device.name)
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text(verbatim: line)
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DS.Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var line: String {
        let platform = device.platform == "android" ? L10n.t("أندرويد", "Android") : L10n.t("آيفون", "iPhone")
        let build = device.build.map { "\($0)" } ?? L10n.t("قبل التسجيل", "unreported")
        return [platform, build, seen].joined(separator: " · ")
    }

    private var seen: String {
        guard let d = device.lastSeen else { return "" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = AppUpdateDates.kuwait
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
        switch days {
        case ..<1: return L10n.t("آخر ظهور اليوم", "seen today")
        case 1: return L10n.t("آخر ظهور أمس", "seen yesterday")
        default: return L10n.t("قبل \(days) أيام", "\(days) days ago")
        }
    }
}
