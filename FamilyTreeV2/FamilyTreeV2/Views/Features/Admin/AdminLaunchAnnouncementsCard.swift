import SwiftUI

// MARK: - «الإعلانات عند الفتح» في «المناسبات والإعلانات» (العينة launch-announcements، الشاشة ٣) — المالك والمدير
//
// «تظهر الحين · N»: كل إعلان لم ينتهِ (مصغّرة الصورة، لمن «الكل»/«N عضو»، «لين <اليوم والوقت>»، نوع الزرّ) بحبّة حمراء
// «إيقاف» (تأكيد ← stopped_at = الآن)، ثم «انتهت» (آخر ١٠). يُنشأ الإعلان من «＋ إعلان جديد» في عنوان البطاقة
// (المنشئ بوضع `launchOnly`)، أو من مكبّر الصوت ← «إرسال إشعار» ← «يظهر عند فتح التطبيق؟».

struct AdminLaunchAnnouncementsCard: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @EnvironmentObject private var memberVM: MemberViewModel
    @EnvironmentObject private var newsVM: NewsViewModel
    @EnvironmentObject private var notificationVM: NotificationViewModel
    @State private var rows: [LaunchAnnouncement]? = nil
    @State private var failed = false
    @State private var stopTarget: LaunchAnnouncement? = nil
    @State private var stoppingId: UUID? = nil
    @State private var stopFailed = false

    private static let endedLimit = 10

    var body: some View {
        let now = Date()
        let all = rows ?? []
        let live = all.filter { !$0.isOver(at: now) }.sorted { ($0.starts ?? now) < ($1.starts ?? now) }
        let ended = Array(all.filter { $0.isOver(at: now) }
            .sorted { Self.endDate($0) > Self.endDate($1) }
            .prefix(Self.endedLimit))
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // «＋ إعلان جديد» — المدخل الواضح (المالك ٢٠٢٦-١١-١٢: كان مخفياً في مكبّر الصوت ← «إرسال إشعار»)
            AdminOccasionsSectionTitle(title: L10n.t("الإعلانات عند الفتح", "Shown when the app opens"),
                                       actionTitle: authVM.isAdmin ? L10n.t("＋ إعلان جديد", "＋ New") : nil,
                                       onAction: openComposer)
            if rows == nil && !failed {
                AdminPageStateCard(.loading(L10n.t("جارٍ التحميل…", "Loading…")))
            } else if failed && rows == nil {
                AdminOccasionsQuietLine(icon: "exclamationmark.triangle",
                                        text: L10n.t("تعذّر تحميل الإعلانات عند الفتح", "Couldn't load the announcements"))
            } else if all.isEmpty {
                AdminOccasionsQuietLine(icon: "rectangle.portrait.on.rectangle.portrait",
                                        text: L10n.t("لا توجد إعلانات تظهر الآن", "No announcements are showing now"))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    groupLabel(L10n.t("تظهر الآن", "Showing now"), count: live.count)
                    if live.isEmpty {
                        Text(L10n.t("لا توجد إعلانات تظهر الآن", "No announcements are showing now"))
                            .dsFont(.footnote)
                            .foregroundColor(DS.Color.textTertiary)
                            .padding(.vertical, DS.Spacing.sm)
                    }
                    ForEach(Array(live.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { AdminRowDivider() }
                        row(item, now: now, live: true)
                    }
                    if !ended.isEmpty {
                        AdminRowDivider()
                        groupLabel(L10n.t("انتهت", "Ended"), count: nil)
                        ForEach(Array(ended.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { AdminRowDivider() }
                            row(item, now: now, live: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminCard()
            }
        }
        .task { await load() }
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
                Task {
                    stoppingId = item.id
                    let ok = await LaunchAnnouncementsService.stop(item.id)
                    stoppingId = nil
                    if !ok { stopFailed = true }
                }
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

    /// المنشئ نفسه بوضع «إعلان عند فتح التطبيق» وحده — بعد الحفظ `launchAnnouncementsChanged` يعيد جلب البطاقة
    private func openComposer() {
        AdminCreateWindow.open(.announcement, announce: AdminAnnounceDraft(launchOnly: true), chooser: false,
                               authVM: authVM, newsVM: newsVM, notificationVM: notificationVM, memberVM: memberVM)
    }

    private func load() async {
        if let list = await LaunchAnnouncementsService.fetchAll() {
            rows = list
            failed = false
        } else {
            failed = true
        }
    }

    private static func endDate(_ item: LaunchAnnouncement) -> Date {
        item.stopped ?? item.ends ?? .distantPast
    }

    private func groupLabel(_ title: String, count: Int?) -> some View {
        HStack {
            Text(title)
                .dsFont(.label)
                .foregroundColor(DS.Color.textSecondary)
            Spacer(minLength: 0)
            if let count {
                Text(verbatim: "\(count)")
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding(.top, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: الصفّ

    private func row(_ item: LaunchAnnouncement, now: Date, live: Bool) -> some View {
        HStack(spacing: DS.Spacing.md) {
            thumbnail(item)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(audience(item))
                    .dsFont(.hubRow)
                    .foregroundColor(DS.Color.textPrimary)
                Text(verbatim: details(item, now: now, live: live))
                    .dsFont(.footnote)
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: DS.Spacing.xs)
            if live {
                if stoppingId == item.id {
                    ProgressView().scaleEffect(DS.Spinner.chipScale)
                } else {
                    AdminPillButton(title: L10n.t("إيقاف", "Stop"), style: .reject) { stopTarget = item }
                        .accessibilityHint(L10n.t("لن يظهر عند فتح التطبيق", "It won't show when the app opens"))
                }
            }
        }
        .padding(.vertical, DS.Spacing.smd)
        .frame(minHeight: DS.Icon.tapTarget)
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

    /// «لين الخميس 9:00 م · زر «حدّث الحين»» / «تبدأ بكرة 9:00 ص · …» / «انتهت 10 نوفمبر» / «أُوقف 10 نوفمبر»
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
