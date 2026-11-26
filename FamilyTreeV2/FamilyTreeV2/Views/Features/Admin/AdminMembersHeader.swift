import SwiftUI

// MARK: - رأس «العائلة» (إعادة تصميم الإدارة U11 — spec C.6، mock 4، اختيار المالك «ب»)
//
// الرأس الكحلي المسطّح (`AdminBandHeader`): «‹ الإدارة» ← العنوان قائمة الأقسام «العائلة ⌄» وفي طرفه «＋» (تسجيل عضو
// جديد، `canRegisterMembers`) و«⋯» («التقارير (PDF)» بالفلاتر والفرع والبحث الحاليين، `isAdmin`) ← سطر الأرقام
// (`AdminHeaderLine`): «2,729 رجل» (هذه القائمة — بلا سهم) · «262 امرأة ‹» (← «نساء العائلة»؛ المراقب ← شجرة النساء) ·
// «50 خارج العائلة ‹» (← «نساء العائلة» على «فرع خارج العائلة»). كل رقم = أول رقم في ما يفتحه (T2). حلقات الرأس ومفتاح
// «شجرة العائلة | شجرة النساء» حُذفا (spec E.9/E.10) — الحلقات باقية في «اليوم» و«الإحصاءات».
// مطويّاً (حين يصعد شريط البحث تحت سطر الرأس): سطر واحد مثبّت فوق التمرير (`AdminMembersCompactBar`): ‹ · «العائلة ⌄ ·
// 2,729» · بحث (يرجع للحقل ويضع المؤشر فيه) · «الفلاتر» بعدده — والشرائح المفعّلة تحته على الأبيض.

/// أرقام رأس «العائلة» — نفس تعريفات «إحصاء الأفراد» (`AdminMemberCounts`): الرجال = الشجرة بلا طلبات الانضمام، النساء =
/// إناث شجرة النساء
struct AdminFamilyCensus: Equatable {
    var counts = AdminMemberCounts()
    /// «خارج العائلة» (طلب المالك ٢٠٢٦-١١-٠٨): ذكور = أبناء البنات (`DaughterSonsIndex`) + أزواج البنات من خارج العائلة؛
    /// إناث = نساء شجرة النساء المعلَّمات `is_outside_family` — لا يدخلون الإجمالي ولا الرجال ولا النساء.
    /// الأحياء فقط (٢٠٢٦-١١-٢٦)
    var outsideMale: Int?
    var outsideFemale: Int?
    var outsideTotal: Int? { outsideMale.flatMap { m in outsideFemale.map { m + $0 } } }
    /// «N لهم حساب» تحت الرجال والنساء وخارج العائلة (طلب المالك ٢٠٢٦-١١-٠٩ — في «العائلة» لا في «اليوم»):
    /// الرجال من قوائم «استخدام التطبيق» (`AdminAccountsStore`)، النساء من ربط عقدتها بحساب (`WomenStore.linkedUserByWoman`)،
    /// وأبناء البنات من `get_members_last_signin` (`signedIn`) لأن السيرفر يستبعدهم من القوائم. nil قبل وصول البيانات
    var menAccounts: Int?
    var womenAccounts: Int?
    var outsideAccounts: Int?

    @MainActor
    static func make(members: [FamilyMember], women: [FamilyMember], signedIn: Set<UUID>? = nil) -> AdminFamilyCensus {
        var c = AdminFamilyCensus()
        let outside = WomenStore.outsideFamilyIds
        c.counts.setMen(from: members)
        c.counts.setWomen(women, excluding: outside)
        let sons = DaughterSonsIndex.shared.ids
        // حساب مراجعة أبل مسجّل كابن بنت — لا يُحسب
        let review = AppConfigValues.shared.reviewAccountIds
        // «خارج العائلة» الأحياء فقط (طلب المالك ٢٠٢٦-١١-٢٦ «المتوفاة شيل من الاحصائيات خارج العائلة ابى بس الاحياء») —
        // متوفوه في قسمهم داخل «فرع خارج العائلة» (`AdminWomenPanel`)
        let sonCount = members.filter { sons.contains($0.id) && $0.hasName && !review.contains($0.id) && $0.isDeceased != true }.count
        if !women.isEmpty {
            let outsideRows = women.filter { outside.contains($0.id) && $0.hasName && $0.isDeceased != true }
            c.outsideMale = sonCount + outsideRows.filter { !$0.isFemale }.count
            c.outsideFemale = outsideRows.filter(\.isFemale).count
            let linked = WomenStore.linkedUserByWoman
            c.womenAccounts = women.filter { $0.isFemale && $0.hasName && !outside.contains($0.id) && linked[$0.id] != nil }.count
            if let signedIn {
                c.outsideAccounts = members.filter { sons.contains($0.id) && $0.hasName && !review.contains($0.id) && signedIn.contains($0.id) }.count
                    + outsideRows.filter { linked[$0.id] != nil }.count
            }
        }
        let accounts = AdminAccountsStore.shared
        if accounts.loaded {
            c.menAccounts = members.filter { m in
                m.role != .pending && m.hasName && !m.isWomanAccount && !sons.contains(m.id) && accounts.info(m.id) != nil
            }.count
        }
        return c
    }
}

// MARK: - سطر الأرقام

/// عناصر سطر الرأس — الصفر والتحميل والفشل لا تظهر رقماً عادياً (`AdminHeaderItemLook`)
enum AdminMembersHeaderItems {
    /// - menHealth: حال قائمة الأعضاء (nil = من القيمة)
    /// - womenHealth: حال شجرة النساء (منها «امرأة» و«خارج العائلة»)
    /// - openWomen/openOutside: nil = رقم بلا سهم
    static func make(census: AdminFamilyCensus, menHealth: AdminStoreHealth?, womenHealth: AdminStoreHealth,
                     retryMen: @escaping () -> Void, retryWomen: @escaping () -> Void,
                     openWomen: (() -> Void)?, openOutside: (() -> Void)?) -> [AdminHeaderItem] {
        let c = census.counts
        let men = c.men
        let women = c.women
        let outside = census.outsideTotal
        // شجرة النساء وصلت (من الكاش أو الجلب) — الأرقام تُعرض ولو فشل تحديث لاحق
        let womenState: AdminStoreHealth = women != nil && !womenHealth.hasData ? .loaded(at: .distantPast) : womenHealth
        return [
            AdminHeaderItem(id: "men", value: men, label: L10n.t("رجل", "men"), health: menHealth, tap: .none,
                            retry: retryMen,
                            spoken: men.map { L10n.t("\(DSNumber.grouped($0)) رجل في هذه القائمة",
                                                     "\(DSNumber.grouped($0)) men in this list") }),
            AdminHeaderItem(id: "women", value: women, label: L10n.t("امرأة", "women"), health: womenState,
                            tap: openWomen.map { AdminPageTap.action($0) } ?? .none, retry: retryWomen,
                            spoken: women.map { L10n.t("\(DSNumber.grouped($0)) امرأة", "\(DSNumber.grouped($0)) women") }),
            AdminHeaderItem(id: "outside", value: outside, label: L10n.t("خارج العائلة", "outside the family"),
                            health: womenState, tap: openOutside.map { AdminPageTap.action($0) } ?? .none,
                            retry: retryWomen,
                            spoken: outside.map { L10n.t("\(DSNumber.grouped($0)) خارج العائلة، أحياء",
                                                         "\(DSNumber.grouped($0)) outside the family, living") }),
        ]
    }
}

// MARK: - أزرار الرأس

/// «＋» و«⋯» في طرف العنوان (زرّان على الأكثر — spec A.3). المراقب بلا شيء
struct AdminMembersHeaderButtons: View {
    /// صفحة «تسجيل عضو جديد» — nil = بلا «＋»
    let register: (() -> AnyView)?
    /// «التقارير (PDF)» بالفلاتر الحالية — nil = بلا «⋯»
    let reports: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if let register {
                // بيته الوحيد (المالك والمدير)
                NavigationLink { AdminLazyPage { register() } } label: {
                    AdminGlassCircle(symbol: "plus")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("تسجيل عضو جديد", "Register a new member"))
            }
            if let reports {
                Menu {
                    Button(action: reports) {
                        Label(L10n.t("التقارير (PDF)", "Reports (PDF)"), systemImage: "doc.richtext")
                    }
                } label: {
                    AdminGlassCircle(symbol: "ellipsis")
                }
                .accessibilityLabel(L10n.t("المزيد", "More"))
                .accessibilityHint(L10n.t("التقارير بالفلاتر الحالية", "Reports with the current filters"))
            }
        }
    }
}

// MARK: - «يحتاج مراجعتك» (spec C.6 البند ١ — صفّ واحد بدل بطاقة المربّعات، E.12)

/// صفّ بإطار يُرى ورمز تنبيه: «يحتاج مراجعتك» وتحته أول قائمتين فيهما أحد و«و4 قوائم» (`AdminReviewHubLogic.summary`)
/// ← صفحة «يحتاج مراجعتك» (`AdminReviewHubPage`). يُخفيه من يضعه حين تصل كل القوائم صفراً
struct AdminMembersReviewRow: View {
    /// nil = لم تصل الأرقام بعد (هيكل)
    let summary: String?

    static var title: String { L10n.t("يحتاج مراجعتك", "Needs your review") }
    /// شكل السطر أثناء التحميل (يُرسم مموّهاً)
    private static var placeholder: String { L10n.t("هل ما زالوا أحياء؟ · بيانات ناقصة", "Still alive? · Missing data") }

    var body: some View {
        NavigationLink {
            AdminLazyPage {
                AnyView(AdminReviewHubPage().adminBackTitle(AdminArea.family.title).adminArea(.family))
            }
        } label: {
            HStack(spacing: DS.Spacing.smd) {
                Image(systemName: "exclamationmark.triangle")
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(DS.Color.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(Self.title)
                        .dsFont(.hubSection)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(verbatim: summary ?? Self.placeholder)
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .redacted(reason: summary == nil ? .placeholder : [])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.xsm)
            .frame(maxWidth: .infinity, minHeight: DS.Hub.rowMinHeightTwoLines, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminMembersFramePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.map { L10n.t("\(Self.title): \($0)", "\(Self.title): \($0)") }
                            ?? L10n.t("\(Self.title): \(AdminStoreHealthText.loading)", "\(Self.title): \(AdminStoreHealthText.loading)"))
        .accessibilityHint(L10n.t("يفتح قوائم المراجعة", "Opens the review lists"))
        .accessibilityAddTraits(.isButton)
    }
}

/// صفّ بإطار يُرى (`DS.Hub.frameStroke`، زاوية ١٢): الضغط تظليل داخل الشكل لا تصغير (spec A.6/A.16)
struct AdminMembersFramePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.cardRadius, style: .continuous)
        return configuration.label
            .background(shape.fill(configuration.isPressed ? DS.Hub.rowPress : DS.Color.cardBackground))
            .overlay(shape.strokeBorder(DS.Hub.frameStroke, lineWidth: DS.Border.width))
            .contentShape(shape)
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

// MARK: - الرأس المطويّ

/// سطر واحد مثبّت فوق التمرير حين يصعد شريط البحث تحت سطر الرأس: ‹ · «العائلة ⌄ · 2,729» · بحث · «الفلاتر» بعدده —
/// والشرائح المفعّلة تحته على الأبيض (تُلغى من هنا أيضاً)
struct AdminMembersCompactBar: View {
    let total: Int?
    let backTitle: String
    let back: () -> Void
    let search: () -> Void
    /// عدد الفلاتر المفعّلة (رقم زرّ «الفلاتر»)
    let filterCount: Int
    let openFilters: () -> Void
    /// الشرائح المفعّلة — nil = بلا فلاتر
    let chips: AnyView?
    /// ارتفاع السطر الكحلي — شريط البحث يُطوى تحته حين يصل إليه
    @Binding var lineHeight: CGFloat
    @Environment(\.dsLandscape) private var landscape

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Spacing.sm) {
                AdminBackLink(title: backTitle, showsTitle: false, action: back)
                AnyView(AdminAreaTitleMenu(title: AdminArea.family.title, count: total.map { DSNumber.grouped($0) },
                                           compact: true))
                Spacer(minLength: DS.Spacing.xs)
                AdminGlassButton(symbol: "magnifyingglass", label: L10n.t("بحث بالاسم أو الرقم", "Search by name or number"),
                                 action: search)
                AdminMembersBandFilterButton(count: filterCount, action: openFilters)
            }
            .frame(minHeight: DS.Hub.compactBar)
            .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
            .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Hub.band.ignoresSafeArea(edges: landscape ? .horizontal : []))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
            if let chips {
                chips
                    .dsLandscapeReadable(maxWidth: DS.Hub.landscapeWidth - 2 * DS.Spacing.lg)
                    .padding(.horizontal, landscape ? DS.Spacing.xxl : DS.Spacing.lg)
                    .padding(.vertical, DS.Spacing.xxs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Hub.background)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(DS.Hub.cardStroke)
                            .frame(height: DS.Border.width)
                            .accessibilityHidden(true)
                    }
            }
        }
    }
}

/// «الفلاتر» فوق الكحلي: كبسولة زجاجية ٣٦ (لمسها ٤٤)، الرمز والاسم أبيض، والعدد كبسولة ذهبية حين يكون فلتر مفعّل
/// (الذهبي على الكحلي فقط — لا عدد أحمر لفلتر)
struct AdminMembersBandFilterButton: View {
    let count: Int
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.xsm) {
                Image(systemName: "line.3.horizontal.decrease")
                    .dsGlyph(DS.Glyph.md, weight: .medium)
                    .accessibilityHidden(true)
                // من أحجام إمكانية الوصول الرمز والعدد فقط — السطر المطويّ لا يتّسع للاسم مع العنوان (الاسم للقارئ الصوتي)
                if !typeSize.isAccessibilitySize {
                    Text(AdminFilterText.filters)
                        .dsFont(.chip)
                        .lineLimit(1)
                }
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Hub.onGold)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .frame(minWidth: DS.Hub.bellBadge, minHeight: DS.Hub.bellBadge)
                        .background(Capsule().fill(DS.Color.accentLight))
                }
            }
            .foregroundColor(DS.Color.headerGlyph)
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DS.Hub.glassButton)
            .background(Capsule().fill(DS.Hub.glass))
            .overlay(Capsule().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
            .dsTapArea(width: DS.Icon.tapTarget, height: DS.Hub.glassButton)
        }
        .buttonStyle(DSScaleButtonStyle())
        .fixedSize()
        .accessibilityLabel(count > 0 ? L10n.t("الفلاتر، \(count) مفعّلة", "Filters, \(count) on") : AdminFilterText.filters)
        .accessibilityHint(L10n.t("يفتح لوحة الفلاتر", "Opens the filters"))
    }
}
