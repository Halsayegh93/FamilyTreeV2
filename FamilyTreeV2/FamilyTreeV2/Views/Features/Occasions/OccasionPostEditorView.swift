import SwiftUI
import UIKit
import PhotosUI

/// شاشة نوع واحد من «بوستات المناسبات» (تنفتح من قائمة الأنواع في OccasionComposerView):
/// خطوات التفاصيل، ثم الشكل والصورة، ثم المعاينة والحفظ أو المشاركة.
struct OccasionPostEditorView: View {
    @ObservedObject var vm: OccasionComposerViewModel
    @ObservedObject private var kit = OccasionKit.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var showMemberPicker = false
    /// «حسينية أخرى» يركّز على حقل المكان للكتابة (عدّاد لكل جهة: men / women)
    @State private var venueFocus: [String: Int] = [:]
    /// «إضافة سطر» في صلة القرابة: يبيّن حقل السطر الثاني وهو فاضي
    @State private var addingRelationLine = false

    private enum Step: Int {
        case details, design, preview

        var title: String {
            switch self {
            case .details: return L10n.t("أضف التفاصيل", "Add the details")
            case .design: return L10n.t("اختر الشكل", "Choose the look")
            case .preview: return L10n.t("عاين واحفظ أو شارك", "Preview and save or share")
            }
        }
    }
    @State private var step: Step = .details

    private var accent: OccasionAccent { vm.template.accent }

    var body: some View {
        composer
            .environment(\.occasionAccent, accent)
            .navigationTitle(vm.template.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: vm.assetKey) { await vm.prepareAssets() }
            .onChange(of: pickerItem) { item in
                Task { await vm.loadPhoto(item) }
            }
            .sheet(item: $vm.shareItem) { item in
                OccasionShareSheet(items: [item.url])
            }
            .sheet(isPresented: $showMemberPicker) {
                OccasionMemberPickerSheet(family: vm.family, preferDeceased: vm.isDeath || vm.template.kind == .solace) { m in
                    withAnimation(DS.Anim.quick) { vm.pickMember(m) }
                }
                .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
            }
            .alert(vm.message ?? "", isPresented: Binding(
                get: { vm.message != nil },
                set: { if !$0 { vm.message = nil } }
            )) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            }
    }

    private var composer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        Text(L10n.t("الخطوة \(step.rawValue + 2) من ٤", "Step \(step.rawValue + 2) of 4"))
                            .dsFont(.caption)
                            .foregroundColor(DS.Color.textSecondary)
                        Text(step.title)
                            .dsFont(.headline)
                            .foregroundColor(DS.Color.textPrimary)
                        ProgressView(value: Double(step.rawValue + 2), total: 4)
                            .tint(accent.ink)
                    }
                    .id("stepTop")

                    switch step {
                    case .details:
                        detailsSection
                    case .design:
                        if vm.template.hasM1 { modelSection }
                        placementSection
                        if vm.hasPhoto { photoSection }
                    case .preview:
                        preview
                        actions
                    }
                }
                .padding(DS.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Color.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                stepControls()
            }
            .onChange(of: step) { _ in
                proxy.scrollTo("stepTop", anchor: .top)
            }
        }
    }

    private func stepControls() -> some View {
        HStack(spacing: DS.Spacing.md) {
            if step != .details {
                DSSecondaryButton(L10n.t("السابق", "Back"), icon: "arrow.backward", color: accent.ink) {
                    step = Step(rawValue: step.rawValue - 1) ?? .details
                }
            }
            if step != .preview {
                DSPrimaryButton(step == .details ? L10n.t("التالي: الشكل", "Next: look")
                                : L10n.t("التالي: المعاينة", "Next: preview"),
                                icon: "arrow.forward", color: accent.fill) {
                    step = Step(rawValue: step.rawValue + 1) ?? .preview
                }
            }
        }
        .disabled(vm.isWorking)
        .padding(DS.Spacing.md)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func postView() -> OccasionPostView {
        OccasionPostView(template: vm.template, size: vm.size, values: vm.values, photo: vm.photo,
                         kit: kit, revision: kit.revision, model: vm.model)
    }

    // MARK: المعاينة

    private var preview: some View {
        let canvas = vm.size.canvas
        return VStack(spacing: DS.Spacing.sm) {
            GeometryReader { geo in
                let scale = geo.size.width / canvas.width
                postView()
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: geo.size.width, height: canvas.height * scale, alignment: .topLeading)
            }
            .aspectRatio(canvas.width / canvas.height, contentMode: .fit)
            .environment(\.layoutDirection, .leftToRight)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.cardBorder, lineWidth: 1)
            )
            .overlay {
                if kit.isLoading || !kit.fontsReady {
                    ProgressView()
                        .padding(DS.Spacing.lg)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
            }
            .frame(maxWidth: 360)
            .dsCardShadow()
            .frame(maxWidth: .infinity)

            Text(L10n.t("المقاس: ", "Size: ") + "\(Int(canvas.width))×\(Int(canvas.height)) · \(vm.size.title) \(vm.size.ratio)")
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
                .frame(maxWidth: .infinity)

            if kit.failed {
                Button {
                    Task { await vm.prepareAssets() }
                } label: {
                    Label(L10n.t("تعذّر تحميل ملفات التصميم — إعادة المحاولة", "Couldn't load design files — retry"),
                          systemImage: "arrow.clockwise")
                        .font(DS.Font.caption1)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: النموذج (١: صورة دائرية فوق — ٢: صورة سداسية جانبية) — مبدّل صغير بسطر واحد

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionTitle(title: L10n.t("النموذج", "Design"), icon: "rectangle.on.rectangle", tint: accent.ink)
            OccasionSegmented(
                options: OccasionModel.allCases.map { .init(id: $0, title: $0.title, icon: $0.icon) },
                selection: Binding(get: { vm.effectiveModel }, set: { vm.model = $0 })
            )
            // نموذج القالب اللي ما فيه صورة (مشاركة العزاء، نموذج ١ للوفاة) يقول «بدون صورة»
            Text(vm.hasPhoto ? vm.effectiveModel.subtitle : L10n.t("بدون صورة", "No photo"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .padding(.horizontal, DS.Spacing.xxs)
        }
    }

    // MARK: مكان النشر — قائمة منسدلة (المنصة + المقاس)

    private var placementSection: some View {
        let places = vm.placements
        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionTitle(title: L10n.t("مكان النشر", "Where to post"), icon: "paperplane.fill", tint: accent.ink)
            OccasionDropdown(
                title: L10n.t("مكان النشر", "Where to post"),
                icon: "paperplane.fill",
                options: places.map(\.title),
                selected: places.firstIndex { $0.id == vm.placement.id } ?? 0,
                onSelect: { i in
                    guard places.indices.contains(i) else { return }
                    withAnimation(DS.Anim.quick) { vm.placement = places[i] }
                },
                details: places.map { "\(Int($0.size.canvas.width))×\(Int($0.size.canvas.height)) · \($0.size.title) \($0.size.ratio)" }
            )
            if vm.size == .story {
                Text(L10n.t("الستوري فيه هوامش أمان فوق وتحت حتى ما تغطيها أزرار التطبيقات.",
                            "Stories keep safe margins at the top and bottom so app buttons don't cover the content."))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, DS.Spacing.xxs)
            }
        }
    }

    // MARK: التفاصيل (اختيارات)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionTitle(title: L10n.t("التفاصيل", "Details"), icon: "checklist", tint: accent.ink)
            HStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("اختر من القوائم — والكتابة متاحة من «نص آخر»", "Pick from the lists — use “Other” to type"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
                Spacer(minLength: 0)
                Button {
                    OccasionHaptic.select()
                    withAnimation(DS.Anim.quick) { vm.resetForm() }
                    addingRelationLine = false
                } label: {
                    Text(L10n.t("بدء من جديد", "Start over"))
                        .dsFont(.caption)
                        .foregroundColor(accent.ink)
                        .dsTapArea(width: OccasionUI.chipHeight, height: OccasionUI.chipHeight)
                }
                .buttonStyle(OccasionPressStyle())
            }
            .padding(.horizontal, DS.Spacing.xxs)
            switch vm.template.kind {
            case .happy: happyForm
            case .death, .deathText: deathForm
            case .solace: solaceForm
            }
        }
    }

    /// له/لها، فقيد/فقيدة — مبدّل متصل
    private func genderChips(_ labels: [String]) -> some View {
        OccasionSegmented(
            options: [.init(id: OccasionGender.male, title: labels[0]), .init(id: OccasionGender.female, title: labels[1])],
            selection: Binding(get: { vm.gender }, set: { g in withAnimation(DS.Anim.quick) { vm.setGender(g) } })
        )
    }

    private func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { vm.sel(key) == 1 },
                set: { on in withAnimation(DS.Anim.quick) { vm.setSel(key, on ? 1 : 0) } })
    }

    // MARK: الاسم (من الشجرة أو كتابة)

    private func nameSection(_ title: String) -> some View {
        OccasionFormCard(title: title, hint: L10n.t("سطر واحد — إذا طال ينختصر تلقائياً", "One line — long names are shortened automatically")) {
            if let m = vm.member {
                selectedMember(m)
                nameFormatPicker("name")
            } else {
                if vm.gender == .male && !vm.family.isEmpty {
                    Button {
                        OccasionHaptic.select()
                        showMemberPicker = true
                    } label: {
                        OccasionButtonLabel(title: L10n.t("اختر من شجرة العائلة", "Pick from the family tree"), icon: "magnifyingglass")
                    }
                    .buttonStyle(OccasionPressStyle())
                }
                OccasionTextInput(
                    text: vm.text("nameTyped"),
                    placeholder: vm.gender == .male && !vm.family.isEmpty
                        ? L10n.t("أو اكتب الاسم هنا", "Or type the name here")
                        : L10n.t("اكتب الاسم", "Type the name")
                )
                if vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    OccasionRequiredHint(text: L10n.t("مطلوب — اختر الاسم من الشجرة أو اكتبه", "Required — pick the name from the tree or type it"))
                } else {
                    nameFormatPicker("name")
                }
            }
        }
    }

    /// صيغة عنصر اسم: «اسم الفقيد: رباعي» + شرائح الصيغ القصيرة (OccasionNameFormatPicker)
    @ViewBuilder
    private func nameFormatPicker(_ key: String) -> some View {
        if let r = vm.nameResolution(key) {
            OccasionNameFormatPicker(resolution: r) { vm.setNameCount(key, $0) }
        }
    }

    private func selectedMember(_ m: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            OccasionMemberAvatar(member: m, size: DS.Icon.rowLarge)
            VStack(alignment: .leading, spacing: 0) {
                Text(vm.nameResolution("name")?.option.name ?? vm.name)
                    .dsFont(.chip)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Spacing.xs) {
                    Text(m.isDeceased == true
                         ? L10n.t("من شجرة العائلة · متوفى", "From the family tree · deceased")
                         : L10n.t("من شجرة العائلة", "From the family tree"))
                    if vm.isLoadingMemberPhoto {
                        ProgressView().controlSize(.mini)
                    }
                }
                .dsFont(OccasionUI.hint)
                .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
            Button {
                OccasionHaptic.select()
                showMemberPicker = true
            } label: {
                Text(L10n.t("تغيير", "Change"))
                    .dsFont(.chipCompact)
                    .foregroundColor(accent.ink)
                    .dsTapArea(width: OccasionUI.chipHeight, height: OccasionUI.chipHeight)
            }
            .buttonStyle(OccasionPressStyle())
            Button {
                OccasionHaptic.select()
                withAnimation(DS.Anim.quick) { vm.clearMember() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .dsGlyph(DS.Glyph.lg, weight: .regular)
                    .foregroundColor(DS.Color.textTertiary)
                    .dsTapArea(width: DS.Glyph.lg, height: DS.Glyph.lg)
            }
            .buttonStyle(OccasionPressStyle())
            .accessibilityLabel(L10n.t("إلغاء الاختيار", "Clear selection"))
        }
        .padding(DS.Spacing.xsm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(accent.ink.opacity(DS.Opacity.tintFillSoft))
        )
    }

    // MARK: التهاني

    private var happyForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // بنفس ترتيب البوست: سطر التهنئة (الصفة + الصيغة) ← الاسم ← المناسبة ← المولود ← الدعاء
            happyRecipient
            nameSection(L10n.t("الاسم", "Name"))
            if vm.template.id == "graduation" {
                graduationCard
            } else {
                occasionCard
            }
            if vm.template.id == "newborn" || vm.template.id == "newbornGirl" {
                babyNameCard
            }
            duaCard(OccasionChoices.duas(vm.template.id, vm.gender))
        }
    }

    /// سطر التهنئة: له/لها + الصفة + الصيغة (بطاقة وحدة)
    private var happyRecipient: some View {
        let honors = OccasionChoices.honorifics(vm.gender)
        let honor = honors.indices.contains(vm.sel("honor")) ? honors[vm.sel("honor")] : honors[0]
        let openings = OccasionChoices.openings(vm.template.id).map { OccasionChoices.composeIntro($0, honor: honor) }
        return OccasionFormCard(title: L10n.t("لمن التهنئة", "Congratulating")) {
            genderChips([L10n.t("له", "Him"), L10n.t("لها", "Her")])
            OccasionDropdown(label: L10n.t("الصفة", "Title"), icon: "person.fill",
                             options: honors, selected: vm.sel("honor")) { vm.setSel("honor", $0) }
            OccasionDropdown(
                label: L10n.t("صيغة التهنئة", "Greeting"),
                icon: "text.quote",
                options: openings,
                selected: vm.sel("opening"),
                onSelect: { vm.setSel("opening", $0) },
                custom: OccasionCustomOption(text: vm.text("introCustom"), placeholder: L10n.t("اكتب سطر التهنئة", "Type the greeting line"))
            )
        }
    }

    private var graduationCard: some View {
        OccasionFormCard(title: L10n.t("التخرج", "Graduation")) {
            OccasionDropdown(label: L10n.t("المرحلة", "Degree"), icon: "graduationcap.fill",
                             options: OccasionChoices.degrees, selected: vm.sel("degree")) { vm.setSel("degree", $0) }
            if vm.sel("degree") > 0 {
                OccasionDropdown(
                    label: L10n.t("الجهة", "Institution"),
                    icon: "building.columns.fill",
                    options: OccasionChoices.institutions,
                    selected: vm.sel("inst"),
                    onSelect: { vm.setSel("inst", $0) },
                    custom: OccasionCustomOption(text: vm.text("instCustom"),
                                                 placeholder: L10n.t("اسم الجامعة أو الكلية", "University or college"),
                                                 label: L10n.t("جهة أخرى", "Other")),
                    searchable: true
                )
            }
        }
    }

    private var occasionCard: some View {
        OccasionFormCard(title: L10n.t("المناسبة", "Occasion")) {
            OccasionDropdown(
                title: L10n.t("المناسبة", "Occasion"),
                icon: "sparkles",
                options: OccasionChoices.occasions(vm.template.id, vm.gender),
                selected: vm.sel("occasion"),
                onSelect: { vm.setSel("occasion", $0) },
                custom: OccasionCustomOption(text: vm.text("occasionCustom"), placeholder: L10n.t("اكتب سطر المناسبة", "Type the occasion line"))
            )
        }
    }

    private var babyNameCard: some View {
        let isBoy = vm.template.id == "newborn"
        let kids = vm.babyNameSuggestions
        return OccasionFormCard(
            title: isBoy ? L10n.t("اسم المولود", "Baby's name") : L10n.t("اسم المولودة", "Baby's name"),
            hint: kids.isEmpty ? nil : L10n.t("أبناؤه من الشجرة — الأحدث أولاً", "His children from the tree — newest first")
        ) {
            OccasionQuickText(text: vm.text("sub"), suggestions: kids, placeholder: L10n.t("اكتب الاسم", "Type the name"))
            if vm.form.txt("sub").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OccasionRequiredHint(text: isBoy ? L10n.t("مطلوب — اكتب اسم المولود", "Required — type the baby's name")
                                                 : L10n.t("مطلوب — اكتب اسم المولودة", "Required — type the baby's name"))
            }
        }
    }

    private func duaCard(_ options: [String]) -> some View {
        OccasionFormCard(title: L10n.t("الدعاء", "Prayer")) {
            OccasionDropdown(
                title: L10n.t("الدعاء", "Prayer"),
                icon: "hands.sparkles.fill",
                options: options,
                selected: vm.sel("dua"),
                onSelect: { vm.setSel("dua", $0) },
                noneLabel: L10n.t("بدون دعاء", "No prayer"),
                custom: OccasionCustomOption(text: vm.text("duaCustom"), placeholder: L10n.t("اكتب الدعاء", "Type the prayer"), multiline: true),
                longText: true
            )
        }
    }

    // MARK: إعلان الوفاة (مع صورة / بدون صورة)

    private var deathForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            deceasedCard
            nameSection(vm.gender == .male ? L10n.t("اسم الفقيد", "Name of the deceased") : L10n.t("اسم الفقيدة", "Name of the deceased"))
            if vm.template.kind == .death {
                relationLinesCard
            } else {
                relationsCard
                funeralCard
                condolenceCard
            }
            venueCard("men")
            venueCard("women")
            deathDuaCard
        }
    }

    /// صلة القرابة (وفاة مع صورة): سطر أو سطرين بنفس الكبسولة. اقتراحات الشجرة تضيف سطراً (ما تستبدل)،
    /// وكل سطر ينحذف، وأقصى شي سطرين.
    private var relationLinesCard: some View {
        let suggestions = vm.relationSuggestions.reduce(into: [String]()) { acc, s in
            if !s.isEmpty && !acc.contains(s) { acc.append(s) }
        }
        let line1 = vm.form.txt("relation").trimmingCharacters(in: .whitespacesAndNewlines)
        let line2 = vm.form.txt("relation2")
        let showSecond = !line2.isEmpty || addingRelationLine
        let full = !vm.canAddRelationLine
        return OccasionFormCard(title: L10n.t("صلة القرابة", "Relation"),
                                hint: L10n.t("سطر أو سطرين — فاضية تختفي", "One or two lines — empty hides it")) {
            if !suggestions.isEmpty {
                OccasionFieldLabel(L10n.t("من شجرة العائلة — اضغط لإضافة سطر", "From the family tree — tap to add a line"))
                OccasionFlowLayout(spacing: OccasionUI.chipSpacing) {
                    ForEach(suggestions, id: \.self) { line in
                        let on = vm.hasRelationLine(line)
                        OccasionSuggestionChip(title: line, isOn: on, enabled: on || !full) {
                            withAnimation(DS.Anim.quick) { vm.toggleRelationSuggestion(line) }
                        }
                    }
                }
            }
            relationLineField("relation", index: 1, removable: !line1.isEmpty || showSecond)
            if showSecond {
                relationLineField("relation2", index: 2, removable: true)
            } else if !line1.isEmpty {
                Button {
                    OccasionHaptic.select()
                    withAnimation(DS.Anim.quick) { addingRelationLine = true }
                } label: {
                    OccasionButtonLabel(title: L10n.t("إضافة سطر ثاني", "Add a second line"), icon: "plus", filled: false)
                }
                .buttonStyle(OccasionPressStyle())
            }
            if full && suggestions.contains(where: { !vm.hasRelationLine($0) }) {
                Text(L10n.t("سطرين كحد أقصى — احذف سطراً لإضافة غيره", "Two lines at most — remove one to add another"))
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    private func relationLineField(_ key: String, index: Int, removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xsm) {
            HStack(spacing: DS.Spacing.xsm) {
                OccasionTextInput(
                    text: vm.text(key),
                    placeholder: index == 1 ? L10n.t("مثال: والد كل من: علي، حسين", "e.g. والد كل من: علي، حسين")
                                            : L10n.t("مثال: شقيق كل من: محمد، أحمد", "e.g. شقيق كل من: محمد، أحمد")
                )
                if removable {
                    Button {
                        OccasionHaptic.select()
                        withAnimation(DS.Anim.quick) {
                            vm.removeRelationLine(key)
                            if vm.form.txt("relation2").isEmpty { addingRelationLine = false }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dsGlyph(DS.Glyph.lg, weight: .regular)
                            .foregroundColor(DS.Color.textTertiary)
                            .dsTapArea(width: DS.Glyph.lg, height: DS.Glyph.lg)
                    }
                    .buttonStyle(OccasionPressStyle())
                    .accessibilityLabel(index == 1 ? L10n.t("حذف السطر الأول", "Remove the first line")
                                                   : L10n.t("حذف السطر الثاني", "Remove the second line"))
                }
            }
            nameFormatPicker(key)
        }
    }

    private var deceasedCard: some View {
        let g = vm.gender
        return OccasionFormCard(title: L10n.t("الفقيد", "The deceased")) {
            genderChips([L10n.t("فقيد", "Male"), L10n.t("فقيدة", "Female")])
            OccasionDropdown(
                label: L10n.t("السطر الأول", "First line"),
                icon: "text.alignright",
                options: OccasionChoices.deathLeads(g),
                selected: vm.sel("lead"),
                onSelect: { vm.setSel("lead", $0) },
                custom: OccasionCustomOption(text: vm.text("leadCustom"))
            )
            OccasionDropdown(
                label: L10n.t("اللقب", "Title"),
                icon: "person.text.rectangle",
                options: OccasionChoices.deathTitles(g),
                selected: vm.sel("title"),
                onSelect: { vm.setSel("title", $0) },
                custom: OccasionCustomOption(text: vm.text("titleCustom"))
            )
        }
    }

    private var relationsCard: some View {
        let male = vm.gender == .male
        return OccasionFormCard(title: L10n.t("القرابة", "Relatives"), hint: L10n.t("أي سطر فاضي يختفي", "Empty lines are hidden")) {
            OccasionFieldLabel(L10n.t("الزوج / الزوجة", "Spouse"))
            OccasionTextInput(text: vm.text("rel1"), placeholder: male ? "زوج: الاسم" : "زوجة: الاسم")
            nameFormatPicker("rel1")
            OccasionFieldLabel(L10n.t("الأبناء", "Children"))
            OccasionQuickText(text: vm.text("rel2"), suggestions: vm.sonsSuggestion,
                              placeholder: male ? "والد كل من: الأسماء" : "والدة كل من: الأسماء")
            nameFormatPicker("rel2")
            OccasionFieldLabel(L10n.t("الإخوان", "Brothers"))
            OccasionQuickText(text: vm.text("rel3"), suggestions: vm.brothersSuggestion,
                              placeholder: male ? "شقيق كل من: الأسماء" : "شقيقة كل من: الأسماء")
            nameFormatPicker("rel3")
        }
    }

    private var funeralCard: some View {
        OccasionFormCard(title: L10n.t("التشييع", "Funeral"), toggle: toggle("funeral")) {
            OccasionFieldPair {
                OccasionDropdown(label: L10n.t("اليوم", "Day"), icon: "calendar",
                                 options: OccasionChoices.funeralDays, selected: vm.sel("fDay")) { vm.setSel("fDay", $0) }
            } second: {
                OccasionDropdown(label: L10n.t("الوقت", "Time"), icon: "clock.fill",
                                 options: OccasionChoices.funeralTimes, selected: vm.sel("fTime")) { vm.setSel("fTime", $0) }
            }
            OccasionDropdown(
                label: L10n.t("المقبرة", "Cemetery"),
                icon: "mappin.and.ellipse",
                options: OccasionChoices.cemeteries,
                selected: vm.sel("cem"),
                onSelect: { vm.setSel("cem", $0) },
                custom: OccasionCustomOption(text: vm.text("cemCustom"), label: L10n.t("مقبرة أخرى", "Other"))
            )
        }
    }

    private var condolenceCard: some View {
        OccasionFormCard(title: L10n.t("بداية العزاء", "Condolences start"), toggle: toggle("cond")) {
            DatePicker(L10n.t("التاريخ", "Date"), selection: $vm.form.condolenceDate, displayedComponents: .date)
                .environment(\.calendar, Calendar(identifier: .gregorian))
                .font(DS.Font.callout)
                .tint(accent.ink)
            OccasionDropdown(label: L10n.t("المدة", "Duration"), icon: "hourglass",
                             options: OccasionChoices.durationLabels, selected: vm.sel("dur")) { vm.setSel("dur", $0) }
        }
    }

    private func venueCard(_ side: String) -> some View {
        OccasionFormCard(
            title: side == "men" ? L10n.t("عزاء الرجال", "Men's condolences") : L10n.t("عزاء النساء", "Women's condolences"),
            toggle: toggle(side)
        ) {
            OccasionFieldLabel(L10n.t("المكان", "Place"))
            OccasionQuickText(
                text: vm.venuePlace(side),
                suggestions: vm.diwaniyas.map(\.title) + OccasionChoices.venuePresets(vm.gender),
                placeholder: L10n.t("ديوان العائلة (إذا تركته فاضي)", "Family diwaniya (if left empty)"),
                accessory: AnyView(OccasionHusseiniyaPicker(place: vm.venuePlace(side)) {
                    vm.pickOtherHusseiniya(side)
                    venueFocus[side, default: 0] += 1
                }),
                focusRequest: venueFocus[side] ?? 0
            )
            OccasionFieldLabel(L10n.t("المنطقة", "Area"))
            OccasionAreaField(text: vm.text("\(side)Area"))
            OccasionDropdown(label: L10n.t("الأوقات", "Times"), icon: "clock.fill",
                             options: OccasionChoices.venueTimeLabels, selected: vm.sel("\(side)Times")) {
                vm.setSel("\(side)Times", $0)
            }
        }
    }

    private var deathDuaCard: some View {
        let options = OccasionChoices.deathDuas(vm.gender).map { pair in
            [pair.0, pair.1].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        return OccasionFormCard(title: L10n.t("الدعاء", "Prayer")) {
            OccasionDropdown(
                title: L10n.t("الدعاء", "Prayer"),
                icon: "hands.sparkles.fill",
                options: options,
                selected: vm.sel("deathDua"),
                onSelect: { vm.setSel("deathDua", $0) },
                noneLabel: L10n.t("بدون دعاء", "No prayer"),
                custom: OccasionCustomOption(text: vm.text("dua1Custom"), placeholder: L10n.t("اكتب الدعاء", "Type the prayer"), multiline: true),
                longText: true
            )
        }
    }

    // MARK: مشاركة العزاء

    private var solaceForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            OccasionFormCard(title: L10n.t("من", "From")) {
                OccasionDropdown(
                    title: L10n.t("من", "From"),
                    icon: "person.3.fill",
                    options: OccasionChoices.solaceFrom,
                    selected: vm.sel("from"),
                    onSelect: { vm.setSel("from", $0) },
                    custom: OccasionCustomOption(text: vm.text("fromCustom"))
                )
            }
            OccasionFormCard(title: L10n.t("إلى", "To"), hint: L10n.t("اسم العائلة المعزّى فيها", "The bereaved family")) {
                OccasionQuickText(text: vm.text("toFamily"), suggestions: Array(vm.familyNames.prefix(16)),
                                  placeholder: L10n.t("مثال: العبدالمحسن", "e.g. العبدالمحسن"))
                if OccasionChoices.solaceFamily(vm.form.txt("toFamily")).isEmpty {
                    OccasionRequiredHint(text: L10n.t("مطلوب — اكتب اسم العائلة", "Required — type the family name"))
                } else {
                    nameFormatPicker("to")
                }
                OccasionDropdown(
                    label: L10n.t("صيغة العائلة", "Family wording"),
                    icon: "text.bubble.fill",
                    options: OccasionChoices.solaceToFormats.map { $0.replacingOccurrences(of: "{x}", with: "…") },
                    selected: vm.sel("toFmt")
                ) { vm.setSel("toFmt", $0) }
            }
            OccasionFormCard(title: L10n.t("الفقيد", "The deceased")) {
                genderChips([L10n.t("فقيد", "Male"), L10n.t("فقيدة", "Female")])
                OccasionDropdown(
                    label: L10n.t("السطر الأول", "First line"),
                    icon: "text.alignright",
                    options: OccasionChoices.solaceLeads(vm.gender),
                    selected: vm.sel("slead"),
                    onSelect: { vm.setSel("slead", $0) },
                    custom: OccasionCustomOption(text: vm.text("sleadCustom"))
                )
            }
            nameSection(vm.gender == .male ? L10n.t("اسم الفقيد", "Name of the deceased") : L10n.t("اسم الفقيدة", "Name of the deceased"))
            duaCard(OccasionChoices.duas("solace", vm.gender))
        }
    }

    // MARK: الصورة

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            DSSectionTitle(title: L10n.t("الصورة", "Photo"), icon: "photo.fill", tint: accent.ink)
            HStack(spacing: DS.Spacing.md) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    OccasionButtonLabel(title: vm.photo.image == nil ? L10n.t("اختيار صورة", "Choose photo") : L10n.t("تغيير الصورة", "Change photo"),
                                        icon: "photo.on.rectangle")
                }
                .buttonStyle(OccasionPressStyle())
                if vm.photo.image != nil {
                    Button {
                        OccasionHaptic.select()
                        vm.removePhoto()
                        pickerItem = nil
                    } label: {
                        Text(L10n.t("إزالة", "Remove"))
                            .dsFont(.chipCompact)
                            .foregroundColor(DS.Color.error)
                            .dsTapArea(width: OccasionUI.chipHeight, height: OccasionUI.chipHeight)
                    }
                    .buttonStyle(OccasionPressStyle())
                }
                Spacer(minLength: 0)
            }
            if vm.photoFromMember {
                Label(L10n.t("صورة العضو من شجرة العائلة — تقدر تغيّرها", "The member's photo from the family tree — you can change it"),
                      systemImage: "checkmark.circle.fill")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.success)
            }
            OccasionSegmented(
                options: [.init(id: false, title: L10n.t("ملوّنة", "Colour"), icon: "paintpalette.fill"),
                          .init(id: true, title: L10n.t("أبيض وأسود", "Black & white"), icon: "circle.lefthalf.filled")],
                selection: $vm.photo.gray
            )
            if vm.photo.image != nil {
                photoSlider(L10n.t("تكبير", "Zoom"), value: $vm.photo.zoom, range: 1...3)
                photoSlider(L10n.t("يمين / يسار", "Left / right"), value: $vm.photo.x, range: 0...100)
                photoSlider(L10n.t("فوق / تحت", "Up / down"), value: $vm.photo.y, range: 0...100)
            }
            Text(L10n.t("الصورة تبقى على جهازك — ما تنرفع لأي مكان.", "The photo stays on your device — it isn't uploaded anywhere."))
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
        }
    }

    private func photoSlider(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textSecondary)
            Slider(value: value, in: range)
                .tint(accent.ink)
        }
    }

    // MARK: الحفظ والمشاركة

    private var actions: some View {
        VStack(spacing: DS.Spacing.md) {
            // بلون النوع (الوفاة: داكن بنص أبيض)
            DSPrimaryButton(L10n.t("حفظ في الصور", "Save to Photos"), icon: "square.and.arrow.down", isLoading: vm.isWorking,
                            color: accent.isDark ? accent.fieldBase : accent.fill) {
                Task { await vm.saveToPhotos() }
            }
            DSSecondaryButton(L10n.t("مشاركة", "Share"), icon: "square.and.arrow.up", color: DS.Color.primary) {
                Task { await vm.share() }
            }
            .disabled(vm.isWorking)
            let missing = vm.missingRequired
            if !missing.isEmpty {
                OccasionRequiredHint(text: L10n.t("قبل الحفظ أكمل: ", "Before saving, fill in: ") + missing.joined(separator: L10n.t("، ", ", ")))
                    .frame(maxWidth: .infinity)
            }
            Text(L10n.t("الصورة تطلع ", "Exports at ") + "\(Int(vm.size.canvas.width))×\(Int(vm.size.canvas.height)) "
                 + L10n.t("بكسل — جاهزة لـ ", "px — ready for ") + vm.placement.title)
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.textTertiary)
                .frame(maxWidth: .infinity)
        }
    }
}

/// ورقة المشاركة (واتساب، انستقرام، حفظ الملف…)
private struct OccasionShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
