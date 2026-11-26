import SwiftUI

// MARK: - رأس «العائلة» (admin v2، اتجاه «أ» «بطاقات العائلة الملوّنة» — الوحدة V2-2، ٢٠٢٦-١١-٢٦)
//
// الرأس الكحلي المسطّح (`AdminBandHeader`) مثل كل صفحات الإدارة: «‹ الإدارة» بالذهبي ← العنوان قائمة الأقسام «العائلة ⌄»
// وفي طرفه دائرتان زجاجيتان ٤٤: «＋» (تسجيل عضو جديد، `canRegisterMembers` × «يعدّل») و«⋯» («التقارير (PDF)» بالتصفية
// والفرع والبحث الحاليين، `isAdmin`) ← سطر ذهبي «كل العائلة» أو اسم الفرع المختار ← ثلاثة مربّعات أرقام زجاجية
// (`AdminMembersKPIRow`): «2,729 رجل» (هذه القائمة — بلا سهم) · «262 امرأة ‹» (← «نساء العائلة»؛ المراقب ← شجرة النساء)
// · «46 حياً خارج العائلة ‹» (← «نساء العائلة» على «فرع خارج العائلة»؛ الأحياء وحدهم). الرقم أبيض والاسم ذهبي والسهم حيث
// يفتح الرقم شيئاً (T2: أول رقم في ما يفتحه = الرقم نفسه) ← حقل البحث الأبيض بعرض الرأس + زرّ «تصفية» الكريمي بعدده
// (`AdminMembersFilterBar`). الأخضر لمسة فقط (عدد «تصفية»، شريط الفرع) — الرأس كحلي.
// مطويّاً (حين يصعد الحقل تحت سطر الرأس): سطر واحد مثبّت فوق التمرير (`AdminMembersCompactBar`): ‹ · «العائلة ⌄ ·
// 2,729» · بحث (يرجع للحقل ويضع المؤشر فيه) · «تصفية» بعدده — والشرائح المفعّلة تحته على الأبيض.

/// نصوص «العائلة» — «تصفية» (كلمة الآيفون العربية، طلب المالك ٢٠٢٦-١١-٢٦) من مكان الطقم الواحد (`AdminFilterText`، F3)
enum AdminMembersText {
    static var filter: String { AdminFilterText.filters }
    static func filterOn(_ n: Int) -> String { AdminFilterText.on(n) }
    static var filterHint: String { AdminFilterText.openHint }
    static var noResults: String { AdminFilterText.noResults }
}

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
    /// «N لهم حساب» تحت الرجال والنساء (طلب المالك ٢٠٢٦-١١-٠٩ — في «العائلة» لا في «اليوم»): الرجال من قوائم «استخدام
    /// التطبيق» (`AdminAccountsStore`)، النساء من ربط عقدتها بحساب (`WomenStore.linkedUserByWoman`). nil قبل وصول البيانات.
    /// «خارج العائلة» الأحياء وحدهم بلا عدد حسابات (طلب المالك ٢٠٢٦-١١-٢٦؛ حُذف `outsideAccounts` و`signedIn` — F2)
    var menAccounts: Int?
    var womenAccounts: Int?

    @MainActor
    static func make(members: [FamilyMember], women: [FamilyMember]) -> AdminFamilyCensus {
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

// MARK: - مربّعات الأرقام الزجاجية (V2-2)

/// رقم من أرقام الرأس + كلمة صغيرة بعده اختيارية («46 حياً»)
struct AdminMembersKPI: Identifiable {
    let item: AdminHeaderItem
    /// بالذهبي بعد الرقم — nil = بلا
    var unit: String? = nil
    var id: String { item.id }
}

extension AdminMembersHeaderItems {
    /// عناصر الرأس نفسها (`make`) مربّعاتٍ: «خارج العائلة» بكلمة «حياً» بعد رقمه
    static func kpis(_ items: [AdminHeaderItem]) -> [AdminMembersKPI] {
        items.map { AdminMembersKPI(item: $0, unit: $0.id == "outside" ? AdminMembersLogic.livingUnit : nil) }
    }
}

/// ثلاثة مربّعات زجاجية بعرض واحد وطول واحد على الكحلي (عمود واحد من أحجام إمكانية الوصول). الشكل والضغطة والحال من
/// `AdminHeaderItemLook` نفسه (الصفر والتحميل باهتان بلا ضغطة، الفشل «—» برمز إعادة المحاولة، المرفوض مخفي)، و«آخر تحديث
/// 9:12» تحتها بعد فشل لاحق
struct AdminMembersKPIRow: View {
    let kpis: [AdminMembersKPI]
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Row: Identifiable {
        let kpi: AdminMembersKPI
        let look: AdminHeaderItemLook
        var id: String { kpi.id }
    }

    var body: some View {
        let rows = kpis.map { Row(kpi: $0, look: $0.item.look) }.filter { !$0.look.hidden }
        let stale = rows.compactMap(\.look.staleSince).min()
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            if typeSize.isAccessibilitySize {
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(rows) { AdminMembersKPIBox(kpi: $0.kpi, look: $0.look) }
                }
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(rows) { AdminMembersKPIBox(kpi: $0.kpi, look: $0.look) }
                }
                // المربّعات الثلاثة بطول أطولها
                .fixedSize(horizontal: false, vertical: true)
            }
            if let stale {
                Text(AdminStoreHealthText.updated(stale))
                    .dsFont(.subtitle)
                    .foregroundColor(DS.Hub.lineZero)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// مربّع رقم واحد: الرقم ١٧ أبيض (والكلمة الصغيرة والسهم بالذهبي) وتحته الاسم ذهبي ١٢
struct AdminMembersKPIBox: View {
    let kpi: AdminMembersKPI
    let look: AdminHeaderItemLook

    private var item: AdminHeaderItem { kpi.item }

    var body: some View {
        if look.retry, let retry = item.retry {
            Button(action: retry) { face }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("\(item.label): \(AdminStoreHealthText.failed)",
                                           "\(item.label): \(AdminStoreHealthText.failed)"))
                .accessibilityHint(AdminStoreHealthText.retry)
        } else if look.opens {
            AdminTapWrap(tap: item.tap, feel: .scale, label: AnyView(face), accessibilityLabel: spoken)
                .accessibilityHint(L10n.t("يفتح القائمة", "Opens the list"))
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken)
        }
    }

    /// «262 امرأة» — أو حال التحميل/الفشل بالكلمات (نفس سطر الرأس `AdminHeaderLine`)
    private var spoken: String {
        if look.retry {
            return L10n.t("\(item.label): \(AdminStoreHealthText.failed)", "\(item.label): \(AdminStoreHealthText.failed)")
        }
        if look.text == AdminStoreHealthText.placeholder {
            return L10n.t("\(item.label): \(AdminStoreHealthText.loading)", "\(item.label): \(AdminStoreHealthText.loading)")
        }
        let base = item.spoken ?? "\(look.text) \(item.label)"
        guard let since = look.staleSince else { return base }
        let stamp = AdminStoreHealthText.updated(since)
        return L10n.t("\(base)، \(stamp)", "\(base), \(stamp)")
    }

    private var face: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.familyControlRadius, style: .continuous)
        let ink = look.dim ? DS.Hub.lineZero : DS.Color.accentLight
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xsm) {
                Text(verbatim: look.text)
                    .dsFont(.statValue)
                    .monospacedDigit()
                    .foregroundColor(look.dim ? DS.Hub.lineZero : DS.Color.headerTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let unit = kpi.unit, !look.dim {
                    Text(unit)
                        .dsFont(.caption)
                        .foregroundColor(ink)
                        .lineLimit(1)
                }
                if look.retry {
                    Image(systemName: "arrow.clockwise")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                        .foregroundColor(ink)
                } else if look.opens {
                    Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                        .dsGlyph(DS.Glyph.sm, weight: .semibold)
                        .foregroundColor(ink)
                }
            }
            Text(item.label)
                .dsFont(.caption)
                .foregroundColor(ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Hub.kpiPadding)
        .padding(.vertical, DS.Spacing.xsm)
        .frame(maxWidth: .infinity, minHeight: DS.Hub.familyKPIMinHeight, maxHeight: .infinity, alignment: .leading)
        .background(shape.fill(DS.Hub.glass))
        .overlay(shape.strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
        .contentShape(shape)
    }
}

// MARK: - أزرار الرأس

/// «＋» و«⋯» في طرف العنوان: دائرتان زجاجيتان ٤٤ مرسومتين (زرّان على الأكثر — spec A.3). المراقب بلا شيء
struct AdminMembersHeaderButtons: View {
    /// صفحة «تسجيل عضو جديد» — nil = بلا «＋»
    let register: (() -> AnyView)?
    /// «التقارير (PDF)» بالتصفية الحالية — nil = بلا «⋯»
    let reports: (() -> Void)?

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            if let register {
                // بيته الوحيد (المالك والمدير)
                NavigationLink { AdminLazyPage { register() } } label: {
                    AdminMembersBandCircle(symbol: "plus")
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
                    AdminMembersBandCircle(symbol: "ellipsis")
                }
                .accessibilityLabel(L10n.t("المزيد", "More"))
                .accessibilityHint(L10n.t("التقارير بالتصفية الحالية", "Reports with the current filter"))
            }
        }
    }
}

/// دائرة زجاجية ٤٤ مرسومة (لمسها هي نفسها) — رمز أبيض
struct AdminMembersBandCircle: View {
    let symbol: String

    var body: some View {
        Image(dsSymbol: symbol)
            .dsGlyph(DS.Glyph.xl, weight: .medium)
            .foregroundStyle(DS.Color.headerGlyph)
            .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
            .background(Circle().fill(DS.Hub.glass))
            .overlay(Circle().strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
            .contentShape(Circle())
    }
}

// MARK: - زرّ «تصفية» في الرأس

/// «تصفية» على الكحلي بجانب الحقل: كريمي بنص كحلي ورمز التصفية، وعدد التصفية المفعّلة في كبسولة خضراء (الأخضر لمسة).
/// ٤٤ طولاً، زاوية الحقل نفسها
struct AdminMembersFilterPill: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Hub.familyControlRadius, style: .continuous)
        Button(action: action) {
            HStack(spacing: DS.Spacing.xsm) {
                Image(systemName: "line.3.horizontal.decrease")
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .accessibilityHidden(true)
                Text(AdminMembersText.filter)
                    .dsFont(.button)
                    .lineLimit(1)
                if count > 0 {
                    Text(verbatim: "\(count)")
                        .dsFont(.badge)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.xsm)
                        .frame(minWidth: DS.Hub.familyFilterBadge, minHeight: DS.Hub.familyFilterBadge)
                        .background(Capsule().fill(DS.Color.palmFill))
                        .accessibilityHidden(true)
                }
            }
            .foregroundColor(DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(minHeight: DS.Icon.tapTarget)
            .background(shape.fill(DS.Color.cardBackgroundSoft))
            // في الداكن الكريمي رمادي غامق — الإطار الزجاجي يفصله عن الكحلي (لا يُرى على الكريمي في الفاتح)
            .overlay(shape.strokeBorder(DS.Hub.glassLine, lineWidth: DS.Border.width))
            .contentShape(shape)
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(count > 0 ? AdminMembersText.filterOn(count) : AdminMembersText.filter)
        .accessibilityHint(AdminMembersText.filterHint)
    }
}

// MARK: - «يحتاج مراجعتك» (V2-2 البند ٣)

/// بطاقة بإطار رملي: مربّع الرمز · «يحتاج مراجعتك» وتحته سطران («363 تواريخ وفاة ناقصة» / «هل ما زالوا أحياء؟») ·
/// حبّة «5 قوائم» (قوائم لا أشخاص) · ‹ ← صفحة «يحتاج مراجعتك» (`AdminReviewHubPage`) كما كانت. يُخفيها من يضعها حين تصل
/// كل القوائم صفراً (`AdminMembersLogic.reviewState`)
struct AdminMembersReviewRow: View {
    /// nil = لم تصل الأرقام بعد (هيكل بشكل البطاقة)
    let card: AdminMembersLogic.ReviewCard?
    @Environment(\.dynamicTypeSize) private var typeSize

    static var title: String { L10n.t("يحتاج مراجعتك", "Needs your review") }
    /// شكل السطرين والحبّة أثناء التحميل (يُرسمان مموّهين)
    private static var placeholder: AdminMembersLogic.ReviewCard {
        AdminMembersLogic.ReviewCard(first: L10n.t("363 تواريخ وفاة ناقصة", "363 missing death dates"),
                                     second: L10n.t("هل ما زالوا أحياء؟", "Still alive?"), lists: 5)
    }

    var body: some View {
        let shown = card ?? Self.placeholder
        // «5 قوائم» بعد وصول كل الأرقام فقط — قبلها الحبّة هيكل بمكانها
        let lists = card?.lists.map(AdminMembersLogic.listsText)
        let pillText = lists ?? AdminMembersLogic.listsText(Self.placeholder.lists ?? 0)
        return NavigationLink {
            AdminLazyPage {
                AnyView(AdminReviewHubPage().adminBackTitle(AdminArea.family.title).adminArea(.family))
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "list.bullet.clipboard")
                    .dsGlyph(DS.Glyph.lg, weight: .medium)
                    .foregroundColor(DS.Color.warning)
                    .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
                    .background(RoundedRectangle(cornerRadius: DS.Hub.tileIconRadius, style: .continuous)
                        .fill(DS.Color.warning.opacity(DS.Opacity.tintFill)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(Self.title)
                        .dsFont(.hubSection)
                        .foregroundColor(DS.Color.textPrimary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: shown.first)
                        if let second = shown.second {
                            Text(verbatim: second)
                        }
                    }
                    .dsFont(.subtitle)
                    .monospacedDigit()
                    .foregroundColor(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .redacted(reason: card == nil ? .placeholder : [])
                    // من أحجام إمكانية الوصول الحبّة تحت السطرين
                    if typeSize.isAccessibilitySize {
                        pill(pillText)
                            .redacted(reason: lists == nil ? .placeholder : [])
                            .padding(.top, DS.Spacing.xs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    pill(pillText)
                        .redacted(reason: lists == nil ? .placeholder : [])
                }
                Image(systemName: L10n.isArabic ? "chevron.left" : "chevron.right")
                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                    .foregroundColor(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Hub.cardPadding)
            .padding(.vertical, DS.Spacing.smd)
            .frame(maxWidth: .infinity, minHeight: DS.Hub.familyReviewMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(AdminMembersFramePressStyle(radius: DS.Hub.familyReviewRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(lists: lists))
        .accessibilityHint(L10n.t("يفتح قوائم المراجعة", "Opens the review lists"))
        .accessibilityAddTraits(.isButton)
    }

    /// «5 قوائم» — كبسولة بلون التنبيه الخافت
    private func pill(_ text: String) -> some View {
        Text(verbatim: text)
            .dsFont(.badge)
            .monospacedDigit()
            .foregroundColor(DS.Color.warning)
            .lineLimit(1)
            .padding(.horizontal, DS.Spacing.smd)
            .frame(minHeight: DS.Hub.familyReviewPill)
            .background(Capsule().fill(DS.Color.warning.opacity(DS.Opacity.tintFill)))
            .fixedSize()
    }

    private func spoken(lists: String?) -> String {
        guard let card else {
            return L10n.t("\(Self.title): \(AdminStoreHealthText.loading)", "\(Self.title): \(AdminStoreHealthText.loading)")
        }
        let parts = [card.first, card.second, lists].compactMap { $0 }
        let joined = parts.joined(separator: L10n.isArabic ? "، " : ", ")
        return L10n.t("\(Self.title): \(joined)", "\(Self.title): \(joined)")
    }
}

/// صفّ بإطار يُرى (`DS.Hub.frameStroke`): الضغط تظليل داخل الشكل لا تصغير (spec A.6/A.16). الزاوية ١٢ افتراضاً، وبطاقة
/// «يحتاج مراجعتك» ١٦
struct AdminMembersFramePressStyle: ButtonStyle {
    var radius: CGFloat = DS.Hub.cardRadius

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return configuration.label
            .background(shape.fill(configuration.isPressed ? DS.Hub.rowPress : DS.Color.cardBackground))
            .overlay(shape.strokeBorder(DS.Hub.frameStroke, lineWidth: DS.Border.width))
            .contentShape(shape)
            .animation(DS.Hub.rowPressAnimation, value: configuration.isPressed)
    }
}

// MARK: - الرأس المطويّ

/// سطر واحد مثبّت فوق التمرير حين يصعد شريط البحث تحت سطر الرأس: ‹ · «العائلة ⌄ · 2,729» · بحث · «تصفية» بعدده —
/// والشرائح المفعّلة تحته على الأبيض (تُلغى من هنا أيضاً)
struct AdminMembersCompactBar: View {
    let total: Int?
    let backTitle: String
    let back: () -> Void
    let search: () -> Void
    /// عدد التصفية المفعّلة (رقم زرّ «تصفية»)
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

/// «تصفية» في السطر المطويّ فوق الكحلي: كبسولة زجاجية ٣٦ (لمسها ٤٤)، الرمز والاسم أبيض، والعدد كبسولة ذهبية حين تكون
/// تصفية مفعّلة (الذهبي على الكحلي فقط — لا عدد أحمر لتصفية)
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
                    Text(AdminMembersText.filter)
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
        .accessibilityLabel(count > 0 ? AdminMembersText.filterOn(count) : AdminMembersText.filter)
        .accessibilityHint(AdminMembersText.filterHint)
    }
}
