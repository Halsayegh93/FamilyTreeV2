import SwiftUI

// MARK: - «الإعلانات عند الفتح» في «المناسبات والإعلانات» (إعادة التصميم ٢٠٢٦-١١-٢٦ — spec C.11 البند ٣، الوحدة U14)
//
// المالك والمدير. صفّ لكل إعلان لم ينتهِ: مصغّرة الصورة · لمن «الكل»/«32 عضو» · «حتى الخميس 9:00 م · زر «حدّث الآن»»
// وحبّة «إيقاف» (تأكيد ← stopped_at = الآن)، ثم «انتهت» (آخر ١٠) سطر عنوان داخل البطاقة بلا أزرار.
// **لا إنشاء هنا** (spec E.16): الإعلان عند الفتح يُنشأ من «＋ إنشاء» ← «إرسال إشعار» ← «يظهر عند فتح التطبيق؟» وحده.
// «إيقاف» = المالك والمدير × «يعدّل» القسم (`canStop`)، وأثناء تجربة دور لا كتابة (`DebugAdminProbe.dryRun`).
// الحالات: هيكل أول التحميل، «تعذّر التحميل» + «أعد المحاولة»، وبعد فشل تحديث تبقى الصفوف و«آخر تحديث» تحتها.

struct AdminLaunchAnnouncementsCard: View {
    /// «إيقاف» (المالك والمدير × «يعدّل» القسم)
    var canStop: Bool = true
    /// سطر الفراغ يدلّ على «＋ إنشاء» لمن يملكه
    var canCreate: Bool = true
    /// كل تغيّر = إعادة جلب (سحب الصفحة للتحديث)
    var refreshToken: Int = 0

    @State private var rows: [LaunchAnnouncement]? = nil
    @State private var health: AdminStoreHealth = .idle
    @State private var stopTarget: LaunchAnnouncement? = nil
    @State private var stoppingId: UUID? = nil
    @State private var stopFailed = false
    /// أُوقفت أثناء تجربة دور (لا كتابة) — تُعرض منتهية
    @State private var dryStopped: Set<UUID> = []

    private static let endedLimit = 10

    var body: some View {
        AdminOccasionsSectionStack(title: L10n.t("الإعلانات عند الفتح", "Shown when the app opens")) {
            content
        }
        .task { await load() }
        .onChange(of: refreshToken) { _ in Task { await load() } }
        .onReceive(NotificationCenter.default.publisher(for: .launchAnnouncementsChanged)) { _ in
            Task { await load() }
        }
        .dsAlert(L10n.t("إيقاف الإعلان؟", "Stop the announcement?"), isPresented: Binding(
            get: { stopTarget != nil },
            set: { if !$0 { stopTarget = nil } }
        ), icon: "stop.circle") {
            Button(L10n.t("إيقاف", "Stop"), role: .destructive) {
                guard let item = stopTarget else { return }
                stopTarget = nil
                stop(item)
            }
            Button(L10n.t("تراجع", "Keep it"), role: .cancel) { stopTarget = nil }
        } message: {
            Text(L10n.t("لن يظهر للأعضاء عند فتح التطبيق بعد الآن.", "Members won't see it when they open the app anymore."))
        }
        .dsAlert(L10n.t("تعذّر الإيقاف", "Couldn't stop"), isPresented: $stopFailed) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.t("حاول مرة أخرى.", "Try again."))
        }
    }

    @ViewBuilder private var content: some View {
        let now = Date()
        let all = rows ?? []
        let live = all.filter { !isOver($0, now) }.sorted { ($0.starts ?? now) < ($1.starts ?? now) }
        let ended = Array(all.filter { isOver($0, now) }
            .sorted { Self.endDate($0) > Self.endDate($1) }
            .prefix(Self.endedLimit))
        if rows == nil {
            switch health.look {
            case .unknown:
                AdminPageStateCard(.error(L10n.t("تعذّر تحميل الإعلانات عند الفتح", "Couldn't load the announcements"),
                                          retry: { Task { await load() } }))
            default:
                AdminPageStateCard(.loading(L10n.t("جارٍ تحميل الإعلانات عند الفتح…", "Loading the announcements…"), rows: 1))
            }
        } else if all.isEmpty {
            AdminOccasionsQuietLine(icon: "rectangle.portrait.on.rectangle.portrait",
                                    text: canCreate
                                        ? L10n.t("لا إعلان عند الفتح. أنشئه من ＋ إنشاء.", "Nothing shows when the app opens. Create one from ＋ Create.")
                                        : L10n.t("لا إعلان عند الفتح.", "Nothing shows when the app opens."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if live.isEmpty {
                    Text(L10n.t("لا إعلان يظهر الآن", "Nothing is showing now"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeight, alignment: .leading)
                }
                ForEach(Array(live.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { AdminRowDivider(inset: Self.textInset) }
                    row(item, now: now, live: true)
                }
                if !ended.isEmpty {
                    AdminRowDivider()
                    groupLine(L10n.t("انتهت", "Ended"))
                    ForEach(Array(ended.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AdminRowDivider(inset: Self.textInset) }
                        row(item, now: now, live: false)
                    }
                }
                if case .failed(let since?) = health {
                    AdminStaleStamp(since: since)
                        .padding(.vertical, DS.Spacing.sm)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .adminCard()
        }
    }

    private func isOver(_ item: LaunchAnnouncement, _ now: Date) -> Bool {
        dryStopped.contains(item.id) || item.isOver(at: now)
    }

    private func load() async {
        health = health.beginning()
        if let list = await LaunchAnnouncementsService.fetchAll() {
            rows = list
            health = health.ending(success: true)
        } else {
            health = health.ending(success: false)
        }
    }

    /// «إيقاف» بعد التأكيد — أثناء تجربة دور لا كتابة ويُصطنع النجاح محلياً
    private func stop(_ item: LaunchAnnouncement) {
        if DebugAdminProbe.dryRun("stop launch announcement \(item.id)") {
            withAnimation(DS.Anim.quick) { _ = dryStopped.insert(item.id) }
            return
        }
        Task {
            stoppingId = item.id
            let ok = await LaunchAnnouncementsService.stop(item.id)
            stoppingId = nil
            if !ok { stopFailed = true }
        }
    }

    private static func endDate(_ item: LaunchAnnouncement) -> Date {
        item.stopped ?? item.ends ?? .distantPast
    }

    /// بداية الفاصل = بداية النص بعد المصغّرة
    private static var textInset: CGFloat { DS.LaunchCard.rowThumbWidth + DS.Spacing.md }

    /// «انتهت» — عنوان مجموعة داخل البطاقة (spec A.5: سطر لا صندوق)
    private func groupLine(_ title: String) -> some View {
        Text(title)
            .dsFont(.sectionTitle)
            .foregroundColor(DS.Color.textSecondary)
            .frame(maxWidth: .infinity, minHeight: DS.Icon.tapTarget, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: الصفّ

    private func row(_ item: LaunchAnnouncement, now: Date, live: Bool) -> some View {
        AdminOccasionsRow(title: audience(item), subtitle: details(item, now: now, live: live)) {
            thumbnail(item)
        } trailing: {
            if live && canStop {
                if stoppingId == item.id {
                    AdminStatePill(title: L10n.t("جارٍ الإيقاف", "Stopping"), tone: .off, isBusy: true)
                } else {
                    AdminPillButton(title: L10n.t("إيقاف", "Stop"), style: .reject) { stopTarget = item }
                        .accessibilityHint(L10n.t("يسأل قبل الإيقاف — لن يظهر عند فتح التطبيق",
                                                  "Asks first — it won't show when the app opens"))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// مصغّرة ٤:٥ كحلية والصورة ملاءمة داخلها (موقّعة عبر `CachedAsyncImage`)
    private func thumbnail(_ item: LaunchAnnouncement) -> some View {
        let width = DS.LaunchCard.rowThumbWidth
        let shape = RoundedRectangle(cornerRadius: DS.LaunchCard.rowThumbRadius, style: .continuous)
        return ZStack {
            shape.fill(DS.LaunchCard.fill)
            CachedAsyncImage(url: item.imageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "photo")
                    .dsGlyph(DS.Glyph.sm)
                    .foregroundColor(DS.Color.textOnPrimary)
            }
        }
        .frame(width: width, height: width / DS.LaunchCard.aspect)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    /// «الكل» · «32 عضو»
    private func audience(_ item: LaunchAnnouncement) -> String {
        guard let ids = item.memberIds, !ids.isEmpty else { return L10n.t("الكل", "Everyone") }
        return AdminAnnounceKit.membersCount(ids.count)
    }

    /// «حتى الخميس 9:00 م · زر «حدّث الآن»» / «تبدأ غداً 9:00 ص · …» / «انتهى 10 نوفمبر» / «أُوقف 10 نوفمبر»
    private func details(_ item: LaunchAnnouncement, now: Date, live: Bool) -> String {
        var parts: [String] = []
        if live {
            if let s = item.starts, s > now {
                parts.append(L10n.t("تبدأ \(AdminAnnounceKit.when(s))", "starts \(AdminAnnounceKit.when(s))"))
            }
            if let e = item.ends {
                parts.append(L10n.t("حتى \(AdminAnnounceKit.when(e))", "until \(AdminAnnounceKit.when(e))"))
            }
        } else if let stopped = item.stopped {
            parts.append(L10n.t("أُوقف \(AdminOccasionsText.shortDate(stopped))", "stopped \(AdminOccasionsText.shortDate(stopped))"))
        } else if dryStopped.contains(item.id) {
            parts.append(L10n.t("أُوقف \(AdminOccasionsText.shortDate(now))", "stopped \(AdminOccasionsText.shortDate(now))"))
        } else if let e = item.ends {
            parts.append(L10n.t("انتهى \(AdminOccasionsText.shortDate(e))", "ended \(AdminOccasionsText.shortDate(e))"))
        }
        if let title = item.buttonText {
            parts.append(L10n.t("زر «\(title)»", "button “\(title)”"))
        } else {
            parts.append(L10n.t("بدون زر", "no button"))
        }
        return parts.joined(separator: " · ")
    }
}
