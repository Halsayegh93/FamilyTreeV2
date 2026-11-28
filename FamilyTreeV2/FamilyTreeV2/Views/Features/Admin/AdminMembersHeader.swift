import SwiftUI

// MARK: - رأس «العائلة» (admin v2، اتجاه «أ» — الوحدة V2-2، ثم F5 «أبسط» ٢٠٢٦-١١-٢٦)
//
// الرأس الكحلي المسطّح (`AdminBandHeader`) مثل كل صفحات الإدارة: «‹ الإدارة» بالذهبي ← العنوان قائمة الأقسام «العائلة ⌄»
// وفي طرفه دائرتان زجاجيتان ٤٤: «＋» (تسجيل عضو جديد، `canRegisterMembers` × «يعدّل») و«⋯» («التقارير (PDF)» بالتصفية
// والفرع والبحث الحاليين `isAdmin` · «نساء العائلة» صفحتها `isAdmin` · «شجرة النساء» تبويب الشجرة) ← سطر ذهبي صغير بما
// تعرضه القائمة («كل العائلة»، أو الفئات المختارة «رجال · نساء»، والفرع) ← حقل البحث الأبيض بعرض الرأس + زرّ «تصفية»
// الكريمي بعدده (`AdminMembersFilterBar`).
// F5 (المالك: «المربعات العلوية … خلهم اسبط و خلهم داخل التصفية»): مربّعات «رجل · امرأة · خارج العائلة» حُذفت — صارت «مَن»
// أول مجموعة في «تصفية» (`AdminPeopleLogic`)، والعدد في سطر النتيجة تحت الرأس.
// مطويّاً (حين يصعد الحقل تحت سطر الرأس): سطر واحد مثبّت فوق التمرير (`AdminMembersCompactBar`): ‹ · «العائلة ⌄ · N»
// (N = عدد النتيجة الحالية) · بحث (يرجع للحقل ويضع المؤشر فيه) · «تصفية» بعدده — والشرائح المفعّلة تحته على الأبيض.

/// نصوص «العائلة» — «تصفية» (كلمة الآيفون العربية، طلب المالك ٢٠٢٦-١١-٢٦) من مكان الطقم الواحد (`AdminFilterText`، F3)
enum AdminMembersText {
    static var filter: String { AdminFilterText.filters }
    static func filterOn(_ n: Int) -> String { AdminFilterText.on(n) }
    static var filterHint: String { AdminFilterText.openHint }
    static var noResults: String { AdminFilterText.noResults }
}

/// أرقام «العائلة» (حلقات «اليوم» و«الإحصاءات» ورأس شجرة النساء؛ كانت مربّعات رأس الصفحة حتى F5 — صارت فئات «مَن» بالقاعدة
/// نفسها في `AdminWomenRows`/`AdminPeopleLogic`) — نفس تعريفات «إحصاء الأفراد» (`AdminMemberCounts`): الرجال = الشجرة بلا
/// طلبات الانضمام، النساء = إناث شجرة النساء
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

// MARK: - أزرار الرأس

/// «＋» و«⋯» في طرف العنوان: دائرتان زجاجيتان ٤٤ مرسومتين (زرّان على الأكثر — spec A.3). «⋯» قائمة أصلية: «التقارير
/// (PDF)» · «نساء العائلة» · «شجرة النساء» — كلٌّ بصلاحيته، والدائرة تختفي بلا عنصر
struct AdminMembersHeaderButtons: View {
    /// صفحة «تسجيل عضو جديد» — nil = بلا «＋»
    let register: (() -> AnyView)?
    /// «التقارير (PDF)» بالتصفية الحالية — nil = بلا
    let reports: (() -> Void)?
    /// صفحة «نساء العائلة» (`AdminWomenPanel`، المالك والمدير) — nil = بلا
    var womenPage: (() -> Void)? = nil
    /// تبويب الشجرة على شجرة النساء — nil = بلا
    var womenTree: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.xsm) {
            // ثلاث دوائر متساوية (طلب المالك ٢٠٢٦-١١-٢٨): ⋯ (حين فيها شيء) · التقارير · تسجيل عضو — أيقونات بلا نصّ
            if let register {
                // بيته الوحيد (المالك والمدير)
                NavigationLink { AdminLazyPage { register() } } label: {
                    AdminMembersBandCircle(symbol: "person.badge.plus")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("تسجيل عضو", "Register a member"))
            }
            // «التقارير» أيقونة ظاهرة لا داخل «⋯» (المالك ٢٠٢٦-١١-٢٧ «التقارير في العائلة خلها ايقونة مو داخل نقاط»)
            if let reports {
                Button(action: reports) {
                    AdminMembersBandCircle(symbol: "doc.text")
                }
                .buttonStyle(DSScaleButtonStyle())
                .accessibilityLabel(L10n.t("التقارير", "Reports"))
            }
            if womenPage != nil || womenTree != nil {
                Menu {
                    if let womenPage {
                        Button(action: womenPage) {
                            Label(AdminWomenPanel.title, systemImage: "person.2")
                        }
                    }
                    if let womenTree {
                        Button(action: womenTree) {
                            Label(L10n.t("شجرة النساء", "Women's tree"), systemImage: "tree")
                        }
                    }
                } label: {
                    AdminMembersBandCircle(symbol: "ellipsis")
                }
                .accessibilityLabel(L10n.t("المزيد", "More"))
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
