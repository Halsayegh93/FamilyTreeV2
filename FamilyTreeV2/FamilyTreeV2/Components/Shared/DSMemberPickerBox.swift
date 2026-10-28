import SwiftUI

// ════════════════════════════════════════════════════════════════════
// مربّع اختيار عضو من العائلة — «المربّع المتطوّر» (طلب المالك ٢٠٢٦-١٠-٠٧:
// «اختيار الزوجة مو الاختيار المربّع المتطوّر»). مستخرج كما هو من «اختيار زوجة من العائلة»
// في حسابي، ويستعمله أيضاً مربّع إدارة شجرة النساء (الزوجة، الزوج، الأم).
// رأس ملوّن ← قسم «البحث» بحقل المربّعات ← قسم «النتيجة»: تحميل (المجسّم يتنفّس)،
// إرشاد بلا أسماء، فاضٍ (مع «إضافة بالاسم»)، أو صفوف: صورة العضو + الاسم + سهم
// (والمختار حالياً بعلامة ✓).
// ════════════════════════════════════════════════════════════════════

struct DSMemberPickerBox: View {
    let title: String
    let subtitle: String
    var icon: String = "person.2.fill"
    /// المرشّحون (مرتّبون مسبقاً)
    let candidates: [FamilyMember]
    @Binding var search: String
    var isLoading: Bool = false
    /// الخصوصية (حسابي): لا تُعرض أسماء حتى يُكتب اسم محدّد بما يكفي (كلمتان أو ٨ أحرف).
    /// false (الإدارة): كل المرشّحين ظاهرون ويُصفّون بالبحث.
    var requiresSpecificQuery: Bool = false
    /// false = لا أسماء قبل الكتابة (اختيار الأب في «إضافة زوجة/أم» — طلب المالك ٢٠٢٦-١٠-٢٥)، والإرشاد مكانها
    var listsAllWhenEmpty: Bool = true
    var searchLabel: String = L10n.t("بحث بالاسم", "Search by name")
    var searchPlaceholder: String = L10n.t("الاسم", "Name")
    /// الإرشاد قبل كتابة اسم محدّد (مع `requiresSpecificQuery` فقط)
    var hintTitle: String = ""
    var hintMessage: String? = nil
    /// لا مرشّحين أصلاً
    var emptyTitle: String = L10n.t("لا توجد نتائج", "No results")
    /// البحث بلا نتيجة
    var noMatchTitle: String = L10n.t("لا توجد نتائج", "No results")
    var emptyMessage: String? = nil
    /// «إضافة بالاسم» داخل الحالة الفاضية — يستلم ما كُتب في البحث
    var onAddByName: ((String) -> Void)? = nil
    /// المختار حالياً — علامة ✓ بدل السهم
    var selectedId: UUID? = nil
    /// اختيار متعدّد (مستلمو الإعلان، الدفعة ١١): المحدّدون بعلامة ✓ والباقون بدائرة فارغة، والضغط يبدّل
    /// (`onPick` يضيف/يزيل). nil = اختيار واحد كما كان
    var selectedIds: Set<UUID>? = nil
    /// زرّ الإجراء في الشريط (مع الاختيار المتعدّد: «تم (N)») — nil = «إلغاء» وحده كما كان
    var doneTitle: String? = nil
    var onDone: (() -> Void)? = nil
    /// تلميح القارئ الصوتي لصفّ المرشّح (مثل «ربطها زوجةً لك»)
    var rowHint: String? = nil
    /// حبر الصورة البديلة — nil = حبر القسم
    var tint: Color? = nil
    /// إجراء بديل بالأحمر في شريط المربّع (مثل «إزالة الأم») — nil = بلا
    var removeTitle: String? = nil
    var onRemove: (() -> Void)? = nil
    /// زرّ صغير تحت النتائج بعد الكتابة («الأب غير موجود؟») — يرسل المكتوب للمضيف (طلب المالك ٢٠٢٦-١٠-٢٥)
    var missingTitle: String? = nil
    /// البحث يبدأ من الاسم الأول (`NameSearch.filter(fromFirstName:)`) — منتقي «أبوها»
    var matchesFromFirstName: Bool = false
    var onMissing: ((String) -> Void)? = nil
    let onPick: (FamilyMember) -> Void
    let onCancel: () -> Void

    @Environment(\.dsSection) private var section
    /// البحث المؤجَّل قليلاً (١٥٠ م ث بعد آخر حرف) — الكتابة تبقى سلسة ولا تُعاد التصفية مع كل حرف (طلب المالك
    /// ٢٠٢٦-١٠-٢٥ «في بطء في الكتابة»)
    @State private var settledSearch = ""
    /// أقصى ما يُرسم من النتائج بعد الكتابة — «ح» وحدها كانت ترسم مئات الصفوف بصورها
    private static let maxShown = 50
    /// القوائم الطويلة (مئات الأعضاء) كسولة؛ القصيرة عادية حتى يُقاس ارتفاع المربّع كاملاً
    private static let lazyThreshold = 40
    private static let specificWords = 2
    private static let specificLength = 8

    private var ink: Color { tint ?? DS.Color.primary.dsChrome(in: section) }

    var body: some View {
        let query = settledSearch.trimmingCharacters(in: .whitespaces)
        let queryWords = query.split(whereSeparator: \.isWhitespace).count
        let queryIsSpecific = queryWords >= Self.specificWords || query.count >= Self.specificLength
        // البحث الدقيق الواحد (`NameSearch`): كل كلمة بداية كلمة بالترتيب، والاسم الأول التام أولاً
        let matched: [FamilyMember] = {
            if requiresSpecificQuery {
                return queryIsSpecific ? NameSearch.filter(candidates, query: query, fromFirstName: matchesFromFirstName) { $0.fullName } : []
            }
            guard !query.isEmpty else { return listsAllWhenEmpty ? candidates : [] }
            return NameSearch.filter(candidates, query: query, fromFirstName: matchesFromFirstName) { $0.fullName.isEmpty ? $0.firstName : $0.fullName }
        }()
        // بعد الكتابة: أول ٥٠ فقط وسطر «اكتب أكثر» — القائمة الكاملة بلا بحث (المنتقيات التي تعرض الكل) كما هي
        let capped = !query.isEmpty && matched.count > Self.maxShown
        let list = capped ? Array(matched.prefix(Self.maxShown)) : matched
        var extras: [DSComposerAction] = []
        if let removeTitle, let onRemove {
            extras.append(DSComposerAction(id: "remove", title: removeTitle, role: .destructive, action: onRemove))
        }
        return DSComposer(
            title: title,
            subtitle: subtitle,
            icon: icon,
            tint: DS.Color.actionNavy,
            actionTitle: doneTitle ?? "",
            actionIcon: "checkmark",
            showsAction: onDone != nil,
            canSubmit: onDone != nil,
            extraActions: extras,
            onSubmit: { onDone?() },
            onCancel: onCancel
        ) {
            DSComposerSection(title: L10n.t("البحث", "Search"), icon: "magnifyingglass",
                              tint: DS.Color.primary, index: 0) {
                DSComposerField(icon: "magnifyingglass",
                                label: searchLabel,
                                placeholder: searchPlaceholder,
                                text: $search)
            }
            DSComposerSection(title: L10n.t("النتيجة", "Result"), icon: "person.crop.circle",
                              tint: DS.Color.accent,
                              trailing: requiresSpecificQuery || isLoading || matched.isEmpty ? nil : "\(matched.count)",
                              index: 1) {
                if isLoading {
                    // التحميل الواحد: المجسّم يتنفّس
                    DSPageLoader(L10n.t("جارٍ التحميل…", "Loading…"), fillsSpace: false)
                        .padding(.vertical, DS.Spacing.md)
                } else if (requiresSpecificQuery && !queryIsSpecific) || (!listsAllWhenEmpty && query.isEmpty) {
                    // الحالة الافتراضية: إرشاد بلا أي أسماء
                    DSEmptyView(hintTitle, message: hintMessage, icon: "magnifyingglass", style: .inline)
                } else if list.isEmpty {
                    // الحالة الفاضية الواحدة (مضغوطة) + زرّها بالمواصفة الواحدة
                    let addAction: (() -> Void)? = onAddByName.map { add in { add(query) } }
                    DSEmptyView(candidates.isEmpty && !requiresSpecificQuery ? emptyTitle : noMatchTitle,
                                message: emptyMessage,
                                icon: "person.fill.questionmark",
                                actionTitle: addAction == nil ? nil : L10n.t("إضافة بالاسم", "Add by name"),
                                actionIcon: addAction == nil ? nil : "plus",
                                compact: true,
                                action: addAction)
                } else if list.count > Self.lazyThreshold {
                    LazyVStack(spacing: DS.Spacing.sm) {
                        ForEach(list) { row($0) }
                    }
                } else {
                    VStack(spacing: DS.Spacing.sm) {
                        ForEach(list) { row($0) }
                    }
                }
                if capped {
                    Text(L10n.t("تظهر أول \(Self.maxShown) من \(matched.count) — اكتب أكثر لتضييق النتائج",
                                "Showing the first \(Self.maxShown) of \(matched.count) — type more to narrow"))
                        .dsFont(.footnote)
                        .foregroundColor(DS.Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            if let missingTitle, let onMissing, !isLoading {   // ظاهر من البداية (طلب المالك) — قبل الكتابة وبعدها
                // رابط نصّي بسيط بلا إطار (طلب المالك ٢٠٢٦-١٠-٢٥ «خل الزر أبسط») — مساحة لمس ٤٤
                Button { onMissing(query) } label: {
                    Text(missingTitle)
                        .dsFont(.footnote)
                        .underline()
                        .foregroundColor(DS.Color.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        // التأجيل: المسح فوري، والكتابة تُصفّى بعد توقّف قصير
        .task(id: search) {
            if search.isEmpty || settledSearch.isEmpty && search.count == 1 && candidates.count < 200 {
                settledSearch = search; return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            settledSearch = search
        }
        // تجهيز كلمات الأسماء في الخلفية عند الفتح — أول حرف لا ينتظر تطبيع آلاف الأسماء
        .task(id: candidates.count) {
            let texts = candidates.map { $0.fullName.isEmpty ? $0.firstName : $0.fullName }
            await Task.detached(priority: .utility) { for t in texts { _ = NameSearch.words(t) } }.value
        }
    }

    private func row(_ m: FamilyMember) -> some View {
        let shownName = m.fullName.isEmpty ? m.firstName : m.displayFullName
        let multi = selectedIds != nil
        let selected = selectedIds?.contains(m.id) ?? (m.id == selectedId)
        return Button { onPick(m) } label: {
            HStack(spacing: DS.Spacing.sm) {
                avatar(m)
                    .saturation(m.isDeceased == true ? 0 : 1)   // المتوفّى: صورة بلا ألوان
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(shownName)
                        .dsFieldFont(.memberName)
                        .foregroundColor(DS.Color.fieldValue)
                        .multilineTextAlignment(.leading)
                    // «متوفى» بنفس شارة بحث الشجرة (طلب المالك ٢٠٢٦-١٠-٢٥ «إذا كان متوفي حط شكل إنه متوفي»)
                    if m.isDeceased == true {
                        DSStatusChip(text: m.isFemale ? L10n.t("متوفاة", "Deceased") : L10n.t("متوفى", "Deceased"),
                                     tint: DS.Color.deceased, size: .mini)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .dsGlyph(DS.Glyph.xl, weight: .regular)
                        .foregroundColor(ink)
                        .accessibilityHidden(true)   // الاختيار يُقرأ من سمة «مُختار»
                } else if multi {
                    // الاختيار المتعدّد: دائرة فارغة بدل السهم (يُحدَّد ولا ينتقل)
                    Image(systemName: "circle")
                        .dsGlyph(DS.Glyph.xl, weight: .regular)
                        .foregroundColor(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                } else {
                    DSChevron()
                }
            }
            .dsRowBox()
        }
        .buttonStyle(DSScaleButtonStyle())
        // القارئ الصوتي: الاسم وحده (الصورة والسهم زخرفة)
        .accessibilityLabel(m.isDeceased == true ? shownName + "، " + L10n.t("متوفى", "deceased") : shownName)
        .accessibilityHint(rowHint ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func avatar(_ m: FamilyMember) -> some View {
        Group {
            if let url = m.avatarUrl ?? m.photoURL, let u = URL(string: url) {
                CachedAsyncImage(url: u) { img in img.resizable().scaledToFill() }
                    placeholder: { ink.opacity(DS.Opacity.tintFill) }
            } else {
                ink.opacity(DS.Opacity.tintFill)
                    .overlay(Image(systemName: "person.fill").foregroundColor(ink))
            }
        }
        .frame(width: DS.Icon.rowLarge, height: DS.Icon.rowLarge)
        .clipShape(Circle())
        .overlay(Circle().stroke(ink.opacity(DS.Opacity.tintFillStrong), lineWidth: DS.Border.width))
        .accessibilityHidden(true)
    }
}
