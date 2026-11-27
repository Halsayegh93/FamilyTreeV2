import SwiftUI
import Supabase

// MARK: - «صلاحيات الأعضاء حسب الفئة» في «الفريق والأمان» (المالك، طلب ٢٠٢٦-١١-٢٧)
//
// بطاقة فئات بصفّ لكل فئة (اسمها، كم مخفي، حبّة «الافتراضي»/«مخصّص») ← صفحة الفئة: الشاشات بمفاتيحها، وكل شاشة تنفتح
// على ما بداخلها بمفاتيحه (الأم المطفأة تُبهت أبناءها — قيمهم تبقى)، ملاحظة «الإبلاغ والحظر يظهران للجميع دائماً»،
// و«إعادة الافتراضي». الحفظ `set_app_config('member_category_access', …)` (المالك وحده؛ فحص السيرفر يرفض الخاطئ)،
// والجدول والقاعدة في `Core/MemberAccess.swift`. الإدارة ترى كل شيء دائماً ولا تدخل الجدول.

/// لون مربّع الفئة — عائلة الكحلي والذهبي بالمعنى
private extension MemberCategory {
    var tint: Color {
        switch self {
        case .familyMan: return DS.Color.navyFill
        case .familyWoman: return DS.Color.femaleFill
        case .daughterSon, .daughterDaughter: return DS.Color.palmFill
        case .limited: return DS.Color.slateFill
        case .incomplete: return DS.Color.goldFill
        case .outsideSpouse: return DS.Color.seaFill
        }
    }
    var title: String { L10n.t(titleAr, titleEn) }
    var who: String { L10n.t(whoAr, whoEn) }
}

private extension MemberScreen {
    var title: String { L10n.t(titleAr, titleEn) }
}

/// بطاقة الفئات — صفّ لكل فئة يفتح صفحتها
struct MemberAccessCategoriesCard: View {
    @ObservedObject private var store = MemberAccessStore.shared

    var body: some View {
        let matrix = store.matrix
        let legacy = store.legacyLimited
        AdminSectionCard(spacing: 0) {
            AdminRowsCardBody {
                ForEach(Array(MemberCategory.allCases.enumerated()), id: \.element) { i, c in
                    AdminTapWrap(tap: .page { AnyView(MemberAccessCategoryPage(category: c)) }, feel: .row, label: AnyView(
                        AdminListRow(icon: c.symbol, tint: c.tint, title: c.title,
                                     subtitle: L10n.t(MemberAccess.summaryAr(category: c, matrix: matrix, legacyLimited: legacy),
                                                      MemberAccess.summaryEn(category: c, matrix: matrix, legacyLimited: legacy))) {
                            let custom = MemberAccess.isCustom(category: c, matrix: matrix)
                            AdminStatePill(title: custom ? L10n.t("مخصّص", "Custom") : L10n.t("الافتراضي", "Default"),
                                           tone: custom ? .warn : .off).fixedSize()
                        }
                    ))
                    // صفوف الفئات تصعد تباعاً مرة عند الظهور — «تقليل الحركة»: تلاشٍ
                    .dsStaggerIn(i)
                }
            }
        }
        .task { await AppConfigValues.shared.refresh() }
    }
}

/// صفحة الفئة: الشاشات وما بداخلها بمفاتيحها
struct MemberAccessCategoryPage: View {
    let category: MemberCategory
    @EnvironmentObject var authVM: AuthViewModel
    @ObservedObject private var store = MemberAccessStore.shared
    @State private var expanded: Set<MemberScreen> = []
    /// ما ضُغط ولم يصل بعد — المفتاح يتحرّك فوراً
    @State private var pending: MemberAccess.Matrix?
    @State private var saving = false
    @State private var errorText: String?
    @State private var confirmReset = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canEdit: Bool { authVM.isOwner }
    private var matrix: MemberAccess.Matrix { pending ?? store.matrix }

    var body: some View {
        AdminPage(header: AdminPageHeader(title: category.title, subtitle: category.who, readOnly: !canEdit),
                  content: AnyView(content))
            .dsAlert(L10n.t("إعادة الافتراضي؟", "Reset to default?"), isPresented: $confirmReset, icon: "arrow.counterclockwise") {
                Button(L10n.t("إعادة", "Reset"), role: .destructive) { save(MemberAccess.resetting(category, matrix: matrix), isReset: true) }
                Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(category == .limited
                     ? L10n.t("ترجع شاشات هذه الفئة كما هي اليوم: الديوانيات والمشاريع والمكتبة وشجرة النساء وتفاصيل العضو مخفية.",
                              "This category goes back to today's screens: diwaniyas, projects, library, women's tree and member details hidden.")
                     : L10n.t("ترجع كل شاشات هذه الفئة ظاهرة كما هي اليوم.", "All screens for this category go back to visible, as today."))
            }
            .dsAlert(L10n.t("تعذّر الحفظ", "Couldn't save"),
                     isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } }),
                     icon: "exclamationmark.triangle.fill") {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
    }

    private var content: some View {
        let legacy = store.legacyLimited
        return VStack(alignment: .leading, spacing: DS.Hub.stackSpacing) {
            AdminSectionCard(title: L10n.t("الشاشات", "Screens"),
                             tag: L10n.t(MemberAccess.summaryAr(category: category, matrix: matrix, legacyLimited: legacy),
                                         MemberAccess.summaryEn(category: category, matrix: matrix, legacyLimited: legacy)),
                             spacing: 0) {
                AdminRowsCardBody {
                    ForEach(MemberScreen.screens, id: \.self) { s in
                        screenRow(s, legacy: legacy)
                        if expanded.contains(s) {
                            // الشاشة مخفية: ما بداخلها مطفأ رمادي، وسطر صغير واحد يقول لماذا
                            if !s.children.isEmpty
                                && !MemberAccess.sees(s, category: category, matrix: matrix, legacyLimited: legacy) {
                                Text(L10n.t("مخفية مع الشاشة", "Hidden with the screen"))
                                    .dsFont(.subtitle)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .padding(.leading, DS.Hub.iconSquare + DS.Spacing.md)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.dsReveal(reduceMotion: reduceMotion))
                            }
                            // ما بداخل الشاشة ينزل قليلاً مع تلاشٍ، ويختفي أسرع — «تقليل الحركة»: تلاشٍ
                            ForEach(s.children, id: \.self) { child in
                                childRow(child, parent: s, legacy: legacy)
                                    .transition(.dsReveal(reduceMotion: reduceMotion))
                            }
                        }
                    }
                }
            }
            DSNoteCard(L10n.t("الإبلاغ والحظر يظهران للجميع دائماً، ولا يُخفيان مع أي شاشة. و«حسابي» نفسه لا يُخفى (حذف الحساب والإعدادات).",
                              "Report and block are always visible to everyone and are never hidden with a screen. “My profile” itself is never hidden (account deletion and settings)."),
                       title: L10n.t("دائماً ظاهر", "Always visible"), icon: "shield.lefthalf.filled", tint: DS.Color.info)
            DSNoteCard(L10n.t("الفئة يحدّدها السيرفر من الحساب نفسه، والإدارة ترى كل شيء. الديوانيات والمشاريع والمكتبة وشجرة النساء ورقم الهاتف تُمنع من السيرفر أيضاً.",
                              "The server decides the category from the account itself; admins see everything. Diwaniyas, projects, library, the women's tree and phone numbers are also blocked on the server."),
                       icon: "info.circle.fill", tint: DS.Color.textSecondary)
            if canEdit && MemberAccess.isCustom(category: category, matrix: matrix) {
                DSButton(L10n.t("إعادة الافتراضي", "Reset to default"), icon: "arrow.counterclockwise", role: .cancel,
                         isLoading: saving) { confirmReset = true }
            }
        }
    }

    // MARK: الصفوف

    private func screenRow(_ s: MemberScreen, legacy: [String]?) -> some View {
        let on = MemberAccess.ownValue(s, category: category, matrix: matrix, legacyLimited: legacy)
        let kids = s.children
        let isOpen = expanded.contains(s)
        let subtitle: String
        if s.isLocked {
            subtitle = L10n.t("دائماً ظاهر · \(kids.count) داخله", "Always visible · \(kids.count) inside")
        } else if !on {
            subtitle = kids.isEmpty ? L10n.t("مخفية", "Hidden") : L10n.t("مخفية — وما بداخلها", "Hidden, with everything inside")
        } else if kids.isEmpty {
            subtitle = s.serverNoteAr.map { L10n.t($0, "Also enforced on the server") } ?? ""
        } else {
            let off = kids.filter { !MemberAccess.ownValue($0, category: category, matrix: matrix, legacyLimited: legacy) }.count
            subtitle = off == 0 ? L10n.t("\(kids.count) داخلها", "\(kids.count) inside")
                                : L10n.t("\(off) من \(kids.count) مخفية بداخلها", "\(off) of \(kids.count) inside hidden")
        }
        return HStack(spacing: DS.Spacing.md) {
            Button {
                guard !kids.isEmpty else { return }
                withAnimation(reduceMotion ? DSMotion.fade : DSMotion.expand) {
                    if isOpen { expanded.remove(s) } else { expanded.insert(s) }
                }
            } label: {
                HStack(spacing: DS.Spacing.md) {
                    AdminIconSquare(symbol: s.symbol, tint: on ? category.tint : DS.Color.slateFill, filled: true)
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        HStack(spacing: DS.Spacing.xs) {
                            Text(s.title)
                                .dsFont(.body)
                                .foregroundColor(DS.Color.textPrimary)
                            if !kids.isEmpty {
                                Image(systemName: "chevron.down")
                                    .dsGlyph(DS.Glyph.sm, weight: .semibold)
                                    .foregroundColor(DS.Color.textTertiary)
                                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                                    .accessibilityHidden(true)
                            }
                        }
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .dsFont(.subtitle)
                                .foregroundColor(DS.Color.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: DS.Spacing.xs)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(kids.isEmpty ? "" : (isOpen ? L10n.t("يخفي ما بداخلها", "Hides what's inside")
                                                           : L10n.t("يعرض ما بداخلها", "Shows what's inside")))
            if s.isLocked {
                AdminStatePill(title: L10n.t("دائماً", "Always"), tone: .ok).fixedSize()
            } else {
                toggle(s, on: on, enabled: true)
            }
        }
        .padding(.vertical, DS.Spacing.xsm)
        .frame(minHeight: DS.Hub.rowMinHeightTwoLines)
    }

    private func childRow(_ s: MemberScreen, parent: MemberScreen, legacy: [String]?) -> some View {
        let on = MemberAccess.ownValue(s, category: category, matrix: matrix, legacyLimited: legacy)
        let parentOn = MemberAccess.sees(parent, category: category, matrix: matrix, legacyLimited: legacy)
        return HStack(spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(s.title)
                    .dsFont(.body)
                    .foregroundColor(parentOn ? DS.Color.textPrimary : DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = s.serverNoteAr, parentOn {
                    Text(L10n.t(note, "Also enforced on the server"))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            Spacer(minLength: DS.Spacing.xs)
            toggle(s, on: on, enabled: parentOn)
        }
        // تحت نصّ أمّها (بعد مربّع الأيقونة)
        .padding(.leading, DS.Hub.iconSquare + DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .frame(minHeight: DS.Hub.rowMinHeight)
        // إطفاء الأم يُبهت أبناءها بتلاشٍ لا قفزة
        .animation(reduceMotion ? DSMotion.fade : DSMotion.enable, value: parentOn)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(parent.title)، \(s.title)")
    }

    private func toggle(_ s: MemberScreen, on: Bool, enabled: Bool) -> some View {
        // المعطّل مع شاشته المخفية يبدو مطفأً (لا أخضر باهت يوحي بأنه ظاهر)
        Toggle(s.title, isOn: Binding(get: { enabled && on }, set: { save(MemberAccess.setting(s, to: $0, category: category, matrix: matrix)) }))
            .labelsHidden()
            .tint(DS.Color.toggleOn)
            .disabled(!canEdit || !enabled)
            .opacity(enabled ? 1 : DS.Opacity.disabled)
            .accessibilityValue(enabled && on ? L10n.t("ظاهر", "Visible") : L10n.t("مخفي", "Hidden"))
    }

    // MARK: الحفظ (المالك — `set_app_config`)

    private struct Params: Encodable {
        let p_key: String
        let p_value: AnyJSON
    }

    private static func json(_ m: MemberAccess.Matrix) -> AnyJSON {
        var root: [String: AnyJSON] = [:]
        for (cat, row) in m.rows where !row.isEmpty {
            root[cat.rawValue] = .object(Dictionary(uniqueKeysWithValues: row.map { ($0.key.rawValue, AnyJSON.bool($0.value)) }))
        }
        return .object(root)
    }

    private func save(_ next: MemberAccess.Matrix, isReset: Bool = false) {
        guard canEdit else { return }
        pending = next
        if DebugAdminProbe.dryRun("set_app_config member_category_access") { return }
        Task {
            saving = true
            defer { saving = false }
            do {
                _ = try await SupabaseConfig.client
                    .rpc("set_app_config", params: Params(p_key: MemberAccess.configKey, p_value: Self.json(next)))
                    .execute()
                await AppConfigValues.shared.refresh(force: true)
                pending = nil
                // لحظة النجاح بعد «إعادة الافتراضي» (لا تأكيد بعدها) — المفاتيح وحدها تكفي نفسها
                if isReset { DSMomentToast.show(L10n.t("تمت إعادة الافتراضي", "Reset to default"), moment: .success) }
            } catch {
                if ErrorHelper.isCancellation(error) { return }
                pending = nil
                errorText = (error as? PostgrestError)?.message ?? error.localizedDescription
            }
        }
    }
}
