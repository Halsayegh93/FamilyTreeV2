import SwiftUI

/// «إرسال إشعار» — إشعار موجّه للأعضاء (الكل، أو دولة، أو أعضاء محدّدون)، يُرسل الآن أو يُجدول.
///
/// بتصميم صفحات الإدارة الموحّد (طلب المالك ٢٠٢٦-٠٩-٢٧). الصفحة تُعرض داخل «الإشعارات والتحديثات»
/// (`AdminMessagingHubView`) تحت بطاقة رأسها وأرقامها الحيّة (المستلمون · تصلهم الإشعارات · مجدول)،
/// فلا تتكرّر بطاقة رأس هنا — مثل «تحديث التطبيق» المضمّنة معها. من الأعلى: شريط المجدولة ← قسم
/// «الإشعار» (العنوان الجاهز/المخصّص + التفاصيل بعدّادها) ← قسم «المستلمون» (الدول بعددها، البحث خلف
/// زر، الكل/إلغاء، صفوف `.dsRowBox()` بعلامة الاختيار) ← شريط سفلي ثابت: «إرسال الآن» كحلي و«جدولة»
/// فاتح + ملخّص الجمهور. التحقق والتأكيد والجدولة والإرسال كما كانت تماماً.
struct AdminNotificationsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var title = "عائلة المحمدعلي 🌿"
    @State private var bodyText = ""
    @State private var selectedMemberIds: Set<UUID> = []
    @State private var searchText = ""
    @State private var displayLimit = 20
    /// تصفية حسب دولة التسجيل (ISO) — nil = الكل
    @State private var countryFilter: String? = nil

    // جدولة الإرسال
    @State private var scheduleEnabled = false
    @State private var scheduledDate = Date().addingTimeInterval(3600)
    @State private var showScheduledSheet = false
    /// شاشة تحديد وقت الجدولة (منتقي الوقت + المجدولة الحالية)
    @State private var showScheduleComposer = false
    /// البحث مخفي خلف زر — يظهر عند الطلب
    @State private var showSearchField = false
    /// العنوان: قائمة جاهزة افتراضياً، ويمكن كتابة عنوان مخصّص
    @State private var useCustomTitle = false
    static let presetTitles = [
        "عائلة المحمدعلي 🌿",
        "إعلان من الإدارة",
        "تذكير",
        "دعوة",
        "تهنئة",
        "تنبيه مهم"
    ]
    @FocusState private var searchFocused: Bool
    /// محرّر التفاصيل — إطاره يتلوّن عند الكتابة (مثل حقول المربّعات)
    @FocusState private var bodyFocused: Bool
    @State private var showSendConfirm = false
    @State private var showSendError = false
    /// الشريحة المختارة بلا أعضاء — لا يُرسل شيء (كانت تتحوّل إرسالاً للجميع — ب-٩)
    @State private var showEmptyAudience = false
    /// انتهى تحميل الفتح — قبله بطاقة «جارٍ تحميل الأعضاء» بدل «لا يوجد أعضاء» المضلِّلة
    @State private var hasLoaded = false
    /// جلب الأعضاء جارٍ (عند الفتح أو «إعادة المحاولة»)
    @State private var isLoadingMembers = false

    /// لون مجال «الرسائل والإشعارات» — نفس بطاقة رأس «الإشعارات والتحديثات» وبلاطتها
    private let pageTint = DS.Color.composerDiwaniya

    /// المستلمون المحتملون — بلا المعلّقين وبلا المتوفّين (طلب المالك):
    /// المتوفّى لا جهاز له ولا معنى لإرسال إشعار باسمه.
    private var activeMembers: [FamilyMember] {
        memberVM.allMembers
            .filter { $0.role != .pending && !($0.isDeceased ?? false) && $0.status != .frozen }
            .filter { m in
                guard let iso = countryFilter else { return true }
                // بلا رقم هاتف = بلا دولة معروفة (٩٨٪ من الأعضاء) فلا يدخل الشريحة
                let phone = (m.phoneNumber ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !phone.isEmpty else { return false }
                return KuwaitPhone.detectCountryAndLocal(phone).country.isoCode == iso
            }
            .sorted { $0.fullName < $1.fullName }
    }

    /// الدول المتاحة للتصفية — فقط التي يوجد بها أعضاء فعلاً.
    private var availableCountries: [(country: KuwaitPhone.Country, count: Int)] {
        let base = memberVM.allMembers.filter { $0.role != .pending && !($0.isDeceased ?? false) }
        var counts: [String: Int] = [:]
        for m in base where !(m.phoneNumber ?? "").isEmpty {
            let iso = KuwaitPhone.detectCountryAndLocal(m.phoneNumber).country.isoCode
            counts[iso, default: 0] += 1
        }
        // الكويت والسعودية تظهران دائماً أولاً (طلب المالك) — ثم باقي الدول الموجودة
        let pinned = ["KW", "SA"]
        let pinnedItems = pinned.compactMap { iso in
            KuwaitPhone.supportedCountries.first { $0.isoCode == iso }.map { ($0, counts[iso] ?? 0) }
        }
        let others = KuwaitPhone.supportedCountries
            .filter { !pinned.contains($0.isoCode) }
            .compactMap { c in counts[c.isoCode].map { (c, $0) } }
            .sorted { $0.1 > $1.1 }
        return (pinnedItems + others).map { (country: $0.0, count: $0.1) }
    }

    private var filteredMembers: [FamilyMember] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return activeMembers }
        return activeMembers.filter {
            $0.fullName.localizedCaseInsensitiveContains(trimmed) ||
            $0.firstName.localizedCaseInsensitiveContains(trimmed) ||
            ($0.phoneNumber ?? "").contains(trimmed)
        }
    }

    // MARK: - Body

    var body: some View {
        // الأقسام تتمرّر معاً (قائمة الأعضاء آخرها) — وشريط الإرسال مثبّت في الأسفل
        // (الصفحة مضمّنة في «الإشعارات والتحديثات» تحت رأسها الملوّن — بلا عنوان خاص بها)
        ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    // شريط الإشعارات المجدولة — يظهر فقط عند وجود إشعارات معلّقة
                    if !notificationVM.scheduledNotifications.isEmpty {
                        scheduledBanner
                            .dsStaggerIn(0)
                    }

                    messageSection

                    recipientsContent
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                sendBar
            }
        .background(DS.Color.background.ignoresSafeArea())
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task {
            await loadData()
            hasLoaded = true
        }
        // مربّعات بمنتصف الشاشة بدل الورقة السفلية (طلب المالك ٢٠٢٦-٠٩-٢٦)
        .dsCenterBox(isPresented: $showScheduleComposer) {
            ScheduleComposerSheet(scheduledDate: $scheduledDate) {
                scheduleEnabled = true
                showScheduleComposer = false
                Task { await sendNotification() }
            }
            .environmentObject(notificationVM)
        }
        .dsCenterBox(isPresented: $showScheduledSheet) {
            ScheduledNotificationsSheet()
                .environmentObject(notificationVM)
                .environmentObject(memberVM)
        }
        // تأكيد الإرسال — يذكر الجمهور صراحةً (البثّ للجميع إجراء لا رجعة فيه)؛
        // مربّع التنبيه الموحّد بالمنتصف (كان ورقة أسفل الشاشة)
        .dsAlert(
            scheduleEnabled ? L10n.t("تأكيد الجدولة", "Confirm Schedule")
                            : L10n.t("تأكيد الإرسال", "Confirm Send"),
            isPresented: $showSendConfirm,
            icon: scheduleEnabled ? "clock.badge.checkmark.fill" : "paperplane.fill"
        ) {
            Button(
                isBroadcastSend
                    ? L10n.t("إرسال للجميع (\(sendAudienceCount))", "Send to all (\(sendAudienceCount))")
                    : L10n.t("إرسال لـ \(sendAudienceCount) عضو", "Send to \(sendAudienceCount) members"),
                role: isBroadcastSend ? .destructive : nil
            ) {
                Task { await sendNotification() }
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(isBroadcastSend
                 ? L10n.t("سيصل هذا الإشعار إلى جميع الأعضاء (\(sendAudienceCount)).",
                          "This will reach all \(sendAudienceCount) members.")
                 : L10n.t("سيصل إلى \(sendAudienceCount) عضو محدّد.",
                          "Will reach \(sendAudienceCount) selected members."))
        }
        .dsAlert(L10n.t("تعذّر الإرسال", "Send Failed"), isPresented: $showSendError) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("حدث خطأ أثناء الإرسال. حاول مرة أخرى.", "Something went wrong. Please try again."))
        }
        .dsAlert(L10n.t("لا يوجد مستلمون", "No Recipients"), isPresented: $showEmptyAudience) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t("لا يوجد أعضاء في هذه الدولة، فلم يُرسل الإشعار لأحد. اختر دولة أخرى أو «الكل».",
                        "There are no members in this country, so nothing was sent. Pick another country or “All”."))
        }
    }

    /// المستلمون الفعليون: `nil` = إعلان للجميع، وقائمة = هؤلاء فقط. مع تصفية الدولة لا يُستخدم
    /// البثّ العام (nil) إطلاقاً — وإلا خرج الإشعار خارج الشريحة المختارة.
    private var sendTargetIds: [UUID]? {
        // إذا كل الأعضاء محددين، نرسل broadcast (nil) بدل إرسال كل الـ IDs
        let activeMemberIds = Set(activeMembers.map(\.id))
        if countryFilter != nil {
            return selectedMemberIds.isEmpty ? Array(activeMemberIds) : Array(selectedMemberIds)
        } else if selectedMemberIds.isEmpty || selectedMemberIds == activeMemberIds {
            return nil
        } else {
            return Array(selectedMemberIds)
        }
    }

    /// شريحة بلا أحد (دولة بلا أعضاء) — رسالة واضحة ولا إرسال، لا تحويل للجميع (ب-٩)
    private var isEmptyAudience: Bool { sendTargetIds?.isEmpty == true }

    /// هل الإرسال بثّ للجميع (تحديد فارغ أو كل النشطين).
    private var isBroadcastSend: Bool {
        let activeMemberIds = Set(activeMembers.map(\.id))
        return selectedMemberIds.isEmpty || selectedMemberIds == activeMemberIds
    }
    /// عدد المستلمين للإرسال الحالي.
    private var sendAudienceCount: Int {
        isBroadcastSend ? activeMembers.count : selectedMemberIds.count
    }

    /// نفس تحميل الفتح السابق تماماً: الأعضاء إن لم يُحمَّلوا بعد، ثم الإشعارات المجدولة
    private func loadData() async {
        if memberVM.allMembers.isEmpty {
            isLoadingMembers = true
            await memberVM.fetchAllMembers()
            isLoadingMembers = false
        }
        await notificationVM.fetchScheduledNotifications()
    }

    // MARK: - المجدولة

    /// الإشعارات المجدولة — شريط «يحتاج انتباهك» يفتح قائمتها (عرض / إلغاء الجدولة)
    private var scheduledBanner: some View {
        let count = notificationVM.scheduledNotifications.count
        return Button {
            showScheduledSheet = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "clock.badge.fill", tint: DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t(
                        "\(count) إشعار مجدول بانتظار الإرسال",
                        "\(count) scheduled — pending send"
                    ))
                    .dsFieldFont(.rowTitle)
                    .foregroundColor(DS.Color.fieldLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Text(L10n.t("تُرسل تلقائياً في موعدها", "Sent automatically on time"))
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
                DSChevron()
            }
            .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
            .padding(.vertical, DS.Spacing.sm)
            // نفس سطح ملاحظة التحذير (`DSNoteCard`) — لكنه صفّ يُضغط فيفتح القائمة
            .background(DSBox.sectionShape.fill(DS.Color.warning.opacity(DS.Opacity.tintFillSoft)))
            .overlay(DSBox.sectionShape
                .strokeBorder(DS.Color.warning.opacity(DS.Opacity.tintStroke), lineWidth: DS.Card.strokeWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - الإشعار (العنوان + التفاصيل)

    private var messageSection: some View {
        DSComposerSection(title: L10n.t("الإشعار", "Notification"),
                          icon: "bell.badge.fill",
                          tint: pageTint,
                          index: 1) {
            titleField
            bodyEditor
        }
    }

    /// العنوان — قائمة منسدلة بعناوين جاهزة (مضغوطة) مع خيار «عنوان مخصّص»
    @ViewBuilder
    private var titleField: some View {
        if useCustomTitle {
            HStack(spacing: DS.Spacing.xs) {
                DSComposerField(icon: "character.cursor.ibeam",
                                label: L10n.t("العنوان", "Title"),
                                placeholder: L10n.t("عنوان الإشعار", "Notification title"),
                                text: $title,
                                tint: pageTint,
                                limit: 100)

                // الرجوع للعناوين الجاهزة
                Button {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                        useCustomTitle = false
                        title = Self.presetTitles.first ?? title
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .dsGlyph(DS.Glyph.md)
                        .foregroundColor(pageTint)
                        .frame(width: DS.Icon.avatar, height: DS.Icon.avatar)
                        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .fill(pageTint.opacity(DS.Opacity.tintFill)))
                        .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)   // مساحة ضغط ٤٤ (توصية أبل)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("عناوين جاهزة", "Preset titles"))
            }
        } else {
            Menu {
                ForEach(Self.presetTitles, id: \.self) { preset in
                    Button(preset) { title = preset }
                }
                Divider()
                Button(L10n.t("عنوان مخصّص…", "Custom title…")) {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                        useCustomTitle = true
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    DSFieldIcon(name: "bell.badge", tint: pageTint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(L10n.t("العنوان", "Title"))
                            .dsFieldFont(.label)
                            .foregroundColor(DS.Color.fieldLabel)
                        Text(title.isEmpty ? L10n.t("اختر عنواناً", "Choose a title") : title)
                            .dsFont(.body)
                            .foregroundColor(title.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .dsGlyph(DS.Glyph.xs)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                }
                .dsRowBox()
                .contentShape(Rectangle())
            }
            .accessibilityHint(L10n.t("يفتح العناوين الجاهزة", "Opens the preset titles"))
        }
    }

    /// التفاصيل (اختياري) — محرّر متعدد الأسطر بإطار حقول المربّعات (يتلوّن عند الكتابة) + عدّاد ٥٠٠
    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "text.alignright")
                    .dsGlyph(DS.Glyph.mdCompact, weight: .semibold)
                    .foregroundColor(bodyFocused ? DS.Color.textOnPrimary : pageTint)
                    .frame(width: DS.Icon.row, height: DS.Icon.row)
                    .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                        .fill(bodyFocused ? pageTint : pageTint.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                Text(L10n.t("التفاصيل", "Details"))
                    .dsFieldFont(.label)
                    .foregroundColor(bodyFocused ? pageTint : DS.Color.fieldLabel)
                Spacer(minLength: 0)
                Text("\(bodyText.count)/500")
                    .dsFont(.micro)
                    .foregroundColor(bodyText.count > 450 ? DS.Color.error : DS.Color.textTertiary)
                    .monospacedDigit()
            }

            ZStack(alignment: .topLeading) {
                if bodyText.isEmpty {
                    Text(L10n.t("تفاصيل (اختياري)", "Details (optional)"))
                        .dsFont(.body)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.horizontal, DS.Spacing.xs)
                        .padding(.vertical, DS.Spacing.sm)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $bodyText)
                    .focused($bodyFocused)
                    .dsFieldFont(.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: DSBox.editorMinHeight, maxHeight: DSBox.editorMaxHeight)
                    .accessibilityLabel(L10n.t("تفاصيل (اختياري)", "Details (optional)"))
                    .onChange(of: bodyText) { _ in
                        if bodyText.count > 500 { bodyText = String(bodyText.prefix(500)) }
                    }
            }
        }
        .padding(.horizontal, DS.Spacing.sm + DS.Spacing.xxs)
        .padding(.vertical, DS.Spacing.sm)
        .dsFocusFieldBox(focused: bodyFocused, tint: pageTint)
    }

    // MARK: - المستلمون

    /// «المستلمون» — أو بطاقة تحميل/خطأ ما دامت قائمة الأعضاء لم تصل
    @ViewBuilder
    private var recipientsContent: some View {
        if memberVM.allMembers.isEmpty && (isLoadingMembers || !hasLoaded) {
            DSPageLoader(L10n.t("جارٍ تحميل الأعضاء…", "Loading members…"), fillsSpace: false)
                .padding(.top, DS.Spacing.md)
                .dsStaggerIn(2)
        } else if memberVM.allMembers.isEmpty && memberVM.membersLoadFailed {
            DSStateCard(icon: "wifi.exclamationmark",
                         title: L10n.t("تعذّر تحميل الأعضاء", "Couldn't load members"),
                         hint: L10n.t("تحقّق من اتصالك وحاول مرة أخرى", "Check your connection and try again"),
                         tint: DS.Color.error,
                         actionTitle: L10n.t("إعادة المحاولة", "Retry"),
                         action: { Task { await loadData() } })
                .padding(.top, DS.Spacing.xs)
                .dsStaggerIn(2)
        } else {
            let members = filteredMembers
            audienceSection(members: members)
            if members.isEmpty {
                noMembersState
                    .dsStaggerIn(3)
            }
        }
    }

    /// الدول ← البحث (عند الطلب) ← الكل/إلغاء ← صفوف الأعضاء. العدد جانب العنوان: المحدّدون، أو
    /// كل الظاهرين إن لم يُحدَّد أحد (نفس عدّاد الشريط السابق)
    private func audienceSection(members: [FamilyMember]) -> some View {
        let trailing = selectedMemberIds.isEmpty
            ? L10n.t("\(members.count) عضو", "\(members.count) members")
            : L10n.t("\(selectedMemberIds.count) محدّد", "\(selectedMemberIds.count) selected")
        return DSComposerSection(title: L10n.t("المستلمون", "Recipients"),
                                 icon: "person.2.fill",
                                 tint: pageTint,
                                 trailing: trailing,
                                 index: 2) {
            // تصفية حسب دولة التسجيل — طلب المالك
            countryChips

            // البحث خلف زر — لا يشغل مساحة إلا عند الحاجة (طلب المالك)
            if showSearchField {
                searchField
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            selectionControls(members: members)

            if !members.isEmpty {
                memberRows(members)
            }
        }
    }

    /// تصفية حسب دولة التسجيل (رقم الهاتف) — تغيير الدولة يمسح التحديد (يخصّ الشريحة الحالية)
    private var countryChips: some View {
        var options: [DSFilterOption<String?>] = [
            DSFilterOption<String?>(id: nil, title: L10n.t("كل الدول", "All"), icon: "globe")
        ]
        for item in availableCountries {
            let name = L10n.isArabic ? item.country.nameArabic : item.country.isoCode
            options.append(DSFilterOption<String?>(id: item.country.isoCode,
                                                   title: "\(item.country.flag) \(name)",
                                                   count: item.count))
        }
        return DSFilterChips(options: options, selection: countrySelection, tint: pageTint)
    }

    private var countrySelection: Binding<String?> {
        Binding(
            get: { countryFilter },
            set: { iso in
                countryFilter = iso
                selectedMemberIds = []      // التحديد يخصّ الشريحة الحالية
            }
        )
    }

    /// حقل البحث — نفس إطار حقول المربّعات، ويُغلق (ويُمسح) من زرّه
    private var searchField: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .dsGlyph(DS.Glyph.md, weight: .semibold)
                .foregroundColor(searchFocused ? pageTint : DS.Color.textTertiary)
                .accessibilityHidden(true)
            TextField(L10n.t("بحث بالاسم أو الرقم...", "Search by name or phone..."), text: $searchText)
                .dsFieldFont(.body)
                .foregroundColor(DS.Color.textPrimary)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .onChange(of: searchText) { _ in displayLimit = 20 }
            Button {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                    searchText = ""
                    showSearchField = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .dsGlyph(DS.Glyph.lgCompact, weight: .regular)
                    .foregroundColor(DS.Color.textTertiary)
                    .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)   // مساحة ضغط ٤٤ (توصية أبل)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -DS.Spacing.sm)
            .accessibilityLabel(L10n.t("إغلاق البحث", "Close search"))
        }
        .padding(.leading, DS.Spacing.md)
        .padding(.trailing, DS.Spacing.xs)
        .frame(minHeight: DSBox.searchHeight)
        .dsFocusFieldBox(focused: searchFocused, tint: pageTint)
    }

    /// زر البحث · تحديد الكل · إلغاء التحديد
    private func selectionControls(members: [FamilyMember]) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            // زر البحث — يفتح حقل البحث عند الحاجة فقط (الشريحة الواحدة، مساحة ضغط ٤٤)
            DSChipButton(L10n.t("بحث", "Search"),
                         icon: showSearchField ? "magnifyingglass.circle.fill" : "magnifyingglass",
                         tint: pageTint, isSelected: showSearchField) {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.15) : DS.Anim.snappy) {
                    showSearchField.toggle()
                }
                if showSearchField { searchFocused = true }
            }

            DSChipButton(L10n.t("الكل", "All"), icon: "checkmark.circle.fill", tint: pageTint) {
                selectedMemberIds = Set(members.map(\.id))
            }
            .accessibilityLabel(L10n.t("تحديد الكل", "Select all"))

            DSChipButton(L10n.t("إلغاء", "Clear"), icon: "xmark.circle.fill", tint: DS.Color.error) {
                selectedMemberIds.removeAll()
            }
            .accessibilityLabel(L10n.t("إلغاء التحديد", "Clear selection"))

            Spacer(minLength: 0)
        }
    }

    /// صفوف الأعضاء (٢٠ في كل مرة) — الضغط يحدّد أو يلغي، و«عرض المزيد» يكمل القائمة
    @ViewBuilder
    private func memberRows(_ members: [FamilyMember]) -> some View {
        LazyVStack(spacing: DS.Spacing.xsm) {
            ForEach(Array(members.prefix(displayLimit))) { member in
                memberRow(member: member)
            }
        }

        if displayLimit < members.count {
            showMoreButton(remaining: members.count - displayLimit)
        }
    }

    // MARK: - Member Row

    /// صف بإطار صفوف المربّعات: الحرف الأول + الاسم (Plex 13.5 عريض) + الرقم (Plex 12) + علامة الاختيار
    private func memberRow(member: FamilyMember) -> some View {
        let selected = selectedMemberIds.contains(member.id)
        return Button {
            toggleSelection(member.id)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                initialBadge(member.displayFullName)

                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(member.displayFullName)
                        .dsFieldFont(.rowTitle)
                        .foregroundColor(DS.Color.fieldLabel)
                        .lineLimit(1)

                    if let phone = member.phoneNumber, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: DS.Spacing.xs) {
                            Image(systemName: "phone.fill")
                                .dsGlyph(DS.Glyph.micro, weight: .semibold)
                                .accessibilityHidden(true)
                            Text(Self.isolatedLTR(KuwaitPhone.display(phone)))
                        }
                        .dsFieldFont(.subtitle)
                        .foregroundColor(DS.Color.fieldValue)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .dsGlyph(DS.Glyph.xl, weight: .semibold)
                    .foregroundColor(selected ? pageTint : DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .dsRowBox()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .strokeBorder(pageTint.opacity(selected ? DS.Opacity.selectedStroke : 0), lineWidth: DS.Border.widthBold)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// الحرف الأول بلون القسم (بدل صورة — مثل قوائم اختيار الأعضاء في المربّعات)
    private func initialBadge(_ name: String) -> some View {
        let first = name.trimmingCharacters(in: .whitespaces).first
        return ZStack {
            Circle().fill(pageTint.opacity(DS.Opacity.tintFill))
            if let first {
                Text(String(first))
                    .dsFont(.rowTitle)
                    .foregroundColor(pageTint)
            } else {
                Image(systemName: "person.fill")
                    .dsGlyph(DS.Glyph.mdCompact, weight: .semibold)
                    .foregroundColor(pageTint)
            }
        }
        .frame(width: DS.Icon.row, height: DS.Icon.row)
        .accessibilityHidden(true)
    }

    private func showMoreButton(remaining: Int) -> some View {
        // الشريحة الواحدة بلون الصفحة (مساحة ضغط ٤٤)
        DSChipButton(L10n.t("عرض المزيد (\(remaining) متبقي)", "Show more (\(remaining) remaining)"),
                     icon: "chevron.down", tint: pageTint) {
            displayLimit += 20
        }
        .frame(maxWidth: .infinity)
    }

    /// لا أعضاء في الشريحة أو البحث (كان «لا يوجد أعضاء» مكان القائمة)
    private var noMembersState: some View {
        let searching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return DSEmptyView(L10n.t("لا يوجد أعضاء", "No members found"),
                           message: searching ? L10n.t("جرّب كلمة أخرى", "Try another word") : nil,
                           style: .compact)
    }

    // MARK: - شريط الإرسال

    /// زرّان أصغر بألوان التطبيق (طلب المالك) — الإرسال أولاً ثم الجدولة: «إرسال الآن» كحلي ممتلئ
    /// (زر المربّعات الأساسي) و«جدولة» فاتح بلون القسم، وتحتهما ملخّص الجمهور
    private var sendBar: some View {
        let noTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: DS.Spacing.xsm) {
            // الزرّ الواحد: «إرسال الآن» بتعبئة القسم، و«جدولة» الثانوي رمادي
            HStack(spacing: DS.Spacing.sm) {
                DSButton(L10n.t("إرسال الآن", "Send Now"), icon: "paperplane.fill",
                         isLoading: notificationVM.isLoading) {
                    scheduleEnabled = false
                    // شريحة بلا أعضاء: رسالة واضحة بدل تأكيد «إرسال للجميع (٠)» (ب-٩)
                    if isEmptyAudience { showEmptyAudience = true } else { showSendConfirm = true }
                }
                .disabled(noTitle)

                DSButton(L10n.t("جدولة", "Schedule"), icon: "clock.badge", role: .cancel) {
                    if isEmptyAudience { showEmptyAudience = true } else { showScheduleComposer = true }
                }
                .disabled(noTitle)
            }

            audienceSummary
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.sm)
        .padding(.bottom, DS.Spacing.sm)
        .background(
            DS.Color.background
                .overlay(alignment: .top) {
                    Rectangle().fill(DS.Color.textTertiary.opacity(DS.Opacity.tintFill)).frame(height: DS.Border.width)
                }
                // الخلفية تكمل لأسفل الشاشة — لا تظهر صفوف الأعضاء تحت الشريط
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// «سيُرسل للجميع» / «لـ N عضو محدد» (أو وقت الجدولة) — ومع «الجميع» عدد من سيصلهم فعلاً
    private var audienceSummary: some View {
        let targetText = selectedMemberIds.isEmpty
            ? L10n.t("للجميع", "to all")
            : L10n.t("لـ \(selectedMemberIds.count) عضو محدد",
                     "to \(selectedMemberIds.count) selected members")
        let summary = scheduleEnabled
            ? L10n.t("سيُجدول الإرسال \(targetText) في \(scheduledDateText)",
                     "Will be scheduled \(targetText) at \(scheduledDateText)")
            : L10n.t("سيُرسل \(targetText)", "Will be sent \(targetText)")
        return HStack(spacing: DS.Spacing.xsm) {
            Text(summary)
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if selectedMemberIds.isEmpty {
                let count = sendAudienceCount
                DSStatusChip(text: "\(count)", icon: "person.2.fill", tint: pageTint)
                    .fixedSize()
                    .accessibilityLabel(L10n.t("\(count) مستلم", "\(count) recipients"))
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedMemberIds.contains(id) {
            selectedMemberIds.remove(id)
        } else {
            selectedMemberIds.insert(id)
        }
    }

    /// الأرقام تبقى بترتيبها من اليسار داخل سطر عربي
    private static func isolatedLTR(_ text: String) -> String {
        "\u{2066}\(text)\u{2069}"
    }

    /// وقت الجدولة منسّقاً حسب لغة الواجهة.
    private var scheduledDateText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: scheduledDate)
    }

    private func sendNotification() async {
        let trimmedBody = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalBody = trimmedBody.isEmpty ? title : trimmedBody

        // مهم: البثّ العام (nil) يصل لكل الأعضاء — فلا يُستخدم إطلاقاً عند تفعيل تصفية الدولة،
        // وشريحة فاضية لا تُرسل شيئاً (كانت قائمة فارغة = «الجميع» — ب-٩)
        let targetIds = sendTargetIds
        if let targetIds, targetIds.isEmpty {
            showEmptyAudience = true
            return
        }

        if scheduleEnabled {
            // الإرسال المجدول — يتولّاه الخادم في الوقت المحدد
            let ok = await notificationVM.scheduleNotification(
                title: title,
                body: finalBody,
                targetMemberIds: targetIds,
                scheduledFor: scheduledDate,
                kind: "admin_broadcast"
            )
            if ok {
                await notificationVM.fetchScheduledNotifications()
                dismiss()
            }
        } else {
            let ok = await notificationVM.sendNotification(
                title: title,
                body: finalBody,
                targetMemberIds: targetIds,
                kind: "admin_broadcast"
            )
            if ok { dismiss() } else { showSendError = true }
        }
    }
}

// MARK: - مربّع الجدولة (تحديد الوقت + المجدولة الحالية)

/// نفس هيكل مربّعات الإضافة (طلب المالك ٢٠٢٦-٠٩-٢٦): رأس متدرّج، أقسام تدخل تباعاً،
/// و«تأكيد الجدولة» كحلي يمين / «إلغاء» رمادي يسار أسفل المربّع.
private struct ScheduleComposerSheet: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @Binding var scheduledDate: Date
    let onConfirm: () -> Void
    /// الوقت الذي فُتح عليه المربّع — «إلغاء» يسأل فقط إذا تغيّر (توصية أبل)
    @State private var startDate: Date? = nil

    private var confirmTitle: String { L10n.t("تأكيد الجدولة", "Confirm schedule") }

    /// وقت مختلف (بالدقيقة — العجلة لا تختار الثواني) عمّا فُتح عليه المربّع
    private var hasChanges: Bool {
        guard let startDate else { return false }
        return Calendar.current.compare(scheduledDate, to: startDate, toGranularity: .minute) != .orderedSame
    }

    var body: some View {
        DSComposer(
            title: L10n.t("جدولة الإشعار", "Schedule"),
            subtitle: L10n.t("اختر وقت إرسال الإشعار", "Pick when the notification goes out"),
            icon: "clock.badge",
            tint: DS.Color.actionNavy,
            actionTitle: confirmTitle,
            actionIcon: "clock.badge.checkmark",
            canSubmit: true,
            isBusy: notificationVM.isLoading,
            hasUnsavedChanges: hasChanges,
            onSubmit: {
                // نفس حماية الضغط المكرّر التي كانت في زر التأكيد السابق (DSPrimaryButton)
                if TapDebouncer.shared.canFire("DSPrimary_\(confirmTitle)") { onConfirm() }
            },
            onCancel: { dismiss() }
        ) {
            timeSection
            pendingSection
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .onAppear { if startDate == nil { startDate = scheduledDate } }
        .task { await notificationVM.fetchScheduledNotifications() }
    }

    // MARK: وقت الإرسال

    private var timeSection: some View {
        DSComposerSection(title: L10n.t("وقت الإرسال", "Send time"), icon: "calendar.badge.clock",
                          tint: AppSection.admin.ink, index: 0) {
            // عجلة واحدة (تاريخ + وقت) — الشكل السابق المرتّب (طلب المالك)
            DatePicker(
                "",
                selection: $scheduledDate,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .tint(AppSection.admin.ink)
            .environment(\.locale, LanguageManager.shared.locale)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: DS.Chart.wheelHeight)
            .clipped()
            // العجلة بعرض البطاقة كاملاً — عرضها ثابت تقريباً فلا تُقصّ أعمدتها على الشاشات الصغيرة
            .padding(.horizontal, -DS.Spacing.md)

            // ملخّص الوقت المختار — صف هادئ بنفس صفوف المربّعات
            HStack(spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "paperplane.fill", tint: AppSection.admin.ink)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(L10n.t("سيُرسل", "Sends"))
                        .dsFieldFont(.label)
                        .foregroundColor(DS.Color.fieldLabel)
                    Text(summaryDateText)
                        .dsFieldFont(.body)
                        .foregroundColor(DS.Color.fieldValue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .dsRowBox()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: المجدولة المعلّقة

    /// قائمة مدمجة بعناوين المجدولة — تظهر فقط عند وجود إشعارات معلّقة
    @ViewBuilder
    private var pendingSection: some View {
        let items = notificationVM.scheduledNotifications
        if !items.isEmpty {
            DSComposerSection(title: L10n.t("مجدولة بانتظار الإرسال", "Pending"),
                              icon: "clock.badge", tint: DS.Color.warning,
                              trailing: "\(items.count)", index: 1) {
                VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
                    ForEach(items) { item in
                        HStack(spacing: DS.Spacing.sm) {
                            Circle()
                                .fill(DS.Color.warning.opacity(DS.Opacity.selectedStroke))
                                .frame(width: DS.Spacing.xsm, height: DS.Spacing.xsm)
                            Text(item.title)
                                .dsFieldFont(.callout)
                                .foregroundColor(DS.Color.fieldValue)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .dsRowBox()
            }
        }
    }

    /// وقت الإرسال المختار — «الجمعة ٢٦ سبتمبر • ٨:٠٠ م»
    private var summaryDateText: String {
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateFormat = L10n.isArabic ? "EEEE d MMMM • h:mm a" : "EEEE d MMM • h:mm a"
        return f.string(from: scheduledDate)
    }
}

// MARK: - مربّع الإشعارات المجدولة (عرض/إلغاء)

/// مربّع عرض بنفس تصميم المربّعات: رأس متدرّج، المجدولة صفوفاً في قسم واحد،
/// و«إغلاق» أسفل المربّع. «إلغاء الجدولة» داخل كل صف كما كان.
private struct ScheduledNotificationsSheet: View {
    @EnvironmentObject var notificationVM: NotificationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var cancellingId: UUID? = nil

    var body: some View {
        let items = notificationVM.scheduledNotifications
        return DSComposer(
            title: L10n.t("الإشعارات المجدولة", "Scheduled"),
            subtitle: L10n.t("تُرسل تلقائياً في موعدها", "Sent automatically on time"),
            icon: "clock.badge.fill",
            tint: DS.Color.actionNavy,
            actionTitle: "",
            showsAction: false,
            cancelTitle: L10n.t("إغلاق", "Close"),
            canSubmit: false,
            onSubmit: {},
            onCancel: { dismiss() }
        ) {
            if items.isEmpty {
                emptyState.dsStaggerIn(0)
            } else {
                DSComposerSection(title: L10n.t("مجدولة بانتظار الإرسال", "Pending"),
                                  icon: "clock.badge", tint: DS.Color.warning,
                                  trailing: "\(items.count)", index: 0) {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(items) { item in row(item) }
                    }
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        .task { await notificationVM.fetchScheduledNotifications() }
    }

    /// الحالة الفارغة الواحدة (مجسّم القسم + عنوان) — كانت رمز SF رمادياً في بطاقة يدوية
    private var emptyState: some View {
        DSEmptyView(L10n.t("لا توجد إشعارات مجدولة", "No scheduled notifications"), style: .inline)
            .dsCard(padding: nil)
    }

    /// صف إشعار مجدول: العنوان والنص، ثم الوقت والجمهور، ثم «إلغاء الجدولة»
    private func row(_ item: NotificationViewModel.ScheduledNotification) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                DSFieldIcon(name: "bell.badge.fill", tint: DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    // العنوان
                    Text(item.title)
                        .dsFieldFont(.headlineCompact)
                        .foregroundColor(DS.Color.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                    // النص (إن اختلف عن العنوان)
                    if !item.body.isEmpty && item.body != item.title {
                        Text(item.body)
                            .dsFieldFont(.callout)
                            .foregroundColor(DS.Color.fieldValue)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            // الوقت + الجمهور
            HStack(spacing: DS.Spacing.sm) {
                metaChip(icon: "calendar", text: timeText(item), color: AppSection.admin.ink)
                metaChip(
                    icon: item.isBroadcast ? "person.3.fill" : "person.2.fill",
                    text: item.isBroadcast
                        ? L10n.t("للجميع", "Everyone")
                        : L10n.t("\(item.targetCount) عضو", "\(item.targetCount) members"),
                    color: DS.Color.accent
                )
                Spacer(minLength: 0)
            }

            // إلغاء الجدولة — الزرّ الواحد بالأحمر (دوّارته داخله أثناء الإلغاء)
            DSButton(L10n.t("إلغاء الجدولة", "Cancel schedule"), icon: "trash", role: .destructive,
                     isLoading: cancellingId == item.id) {
                Task {
                    cancellingId = item.id
                    await notificationVM.cancelScheduledNotification(item.id)
                    cancellingId = nil
                }
            }
            .disabled(cancellingId != nil)
        }
        .dsRowBox()
    }

    private func metaChip(icon: String, text: String, color: Color) -> some View {
        DSStatusChip(text: text, icon: icon, tint: color)
    }

    private func timeText(_ item: NotificationViewModel.ScheduledNotification) -> String {
        guard let d = item.scheduledDate else { return item.scheduledFor }
        let f = DateFormatter()
        f.locale = LanguageManager.shared.locale
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }
}
