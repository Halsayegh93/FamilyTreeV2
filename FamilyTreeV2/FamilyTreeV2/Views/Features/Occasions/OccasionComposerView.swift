import SwiftUI
import UIKit
import PhotosUI

/// بوستات المناسبات — للإدارة والمشرفين (canModerate).
/// كل شي اختيار بدل الكتابة: القالب، النموذج (١ أو ٢)، مكان النشر (يحدد المقاس)، الاختيارات، الاسم من شجرة العائلة
/// (وتنزل معه صورته وسطور القرابة)، الصورة («مع صورة / بدون صورة» للتهاني)، ثم حفظ في الصور أو مشاركة.
struct OccasionComposerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @StateObject private var vm = OccasionComposerViewModel()
    @StateObject private var diwaniyasVM = DiwaniyasViewModel()
    @StateObject private var familyNamesVM = FamilyNamesViewModel()
    @ObservedObject private var kit = OccasionKit.shared
    @State private var pickerItem: PhotosPickerItem?
    @State private var showMemberPicker = false

    var body: some View {
        Group {
            if authVM.canModerate {
                composer
            } else {
                DSEmptyState(
                    icon: "lock.fill",
                    title: L10n.t("هذي الصفحة للإدارة والمشرفين", "Admins and moderators only")
                )
            }
        }
        .navigationTitle(L10n.t("بوستات المناسبات", "Occasion Posts"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: vm.assetKey) { await vm.prepareAssets() }
        .task { await loadData() }
        .onChange(of: memberVM.membersVersion) { _ in
            vm.updateFamily(memberVM.allMembers)
        }
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
        }
        .alert(vm.message ?? "", isPresented: Binding(
            get: { vm.message != nil },
            set: { if !$0 { vm.message = nil } }
        )) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        }
    }

    /// أعضاء الشجرة + الديوانيات + أسماء العوائل (للاختيارات)
    private func loadData() async {
        vm.updateFamily(memberVM.allMembers)
        if memberVM.allMembers.isEmpty {
            await memberVM.fetchAllMembers()
            vm.updateFamily(memberVM.allMembers)
        }
        await diwaniyasVM.fetchDiwaniyas()
        vm.updateDiwaniyas(diwaniyasVM.diwaniyas)
        await familyNamesVM.fetch()
        vm.updateFamilyNames(familyNamesVM.activeNames)
    }

    private var composer: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                    preview.id("preview")
                    templateSection
                    if vm.template.hasModel1 { modelSection }
                    placementSection
                    detailsSection
                    // التهاني: القسم دايماً (فيه «بدون صورة»)؛ الوفاة مع صورة: الصورة؛ الباقي بدون صورة
                    if vm.template.photoOptional || vm.showsPhoto { photoSection }
                    actions
                }
                .padding(DS.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(DS.Color.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { bottomBar(proxy) }
        }
    }

    private func postView() -> OccasionPostView {
        OccasionPostView(template: vm.template, size: vm.size, values: vm.values, photo: vm.photo,
                         kit: kit, revision: kit.revision, model: vm.model, withPhoto: vm.withPhoto)
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

    // MARK: الشريط السفلي — معاينة مصغّرة + حفظ ومشاركة (يبين البوست وانت تختار)

    private func bottomBar(_ proxy: ScrollViewProxy) -> some View {
        let canvas = vm.size.canvas
        let thumbHeight: CGFloat = 64
        let s = thumbHeight / canvas.height
        return HStack(spacing: DS.Spacing.md) {
            Button {
                withAnimation(DS.Anim.medium) { proxy.scrollTo("preview", anchor: .top) }
            } label: {
                postView()
                    .scaleEffect(s, anchor: .topLeading)
                    .frame(width: canvas.width * s, height: thumbHeight, alignment: .topLeading)
                    .environment(\.layoutDirection, .leftToRight)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(DS.Color.cardBorder, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.t("عرض المعاينة", "Show preview"))

            VStack(alignment: .leading, spacing: 2) {
                Text(vm.template.title)
                    .font(DS.Font.calloutBold)
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(1)
                Text("\(Int(canvas.width))×\(Int(canvas.height)) · \(vm.placement.title)")
                    .font(DS.Font.caption2)
                    .foregroundColor(DS.Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if vm.isWorking {
                ProgressView()
                    .frame(width: 44, height: 44)
            } else {
                Group {
                    barButton("square.and.arrow.down", label: L10n.t("حفظ في الصور", "Save to Photos")) {
                        Task { await vm.saveToPhotos() }
                    }
                    barButton("square.and.arrow.up", label: L10n.t("مشاركة", "Share")) {
                        Task { await vm.share() }
                    }
                }
                .opacity(vm.missing.isEmpty ? 1 : 0.5)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func barButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DS.Font.scaled(17, weight: .semibold))
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DS.Color.primary))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: القالب

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("القالب", "Template"), icon: "square.grid.2x2.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(vm.templates) { t in
                        let on = t.id == vm.template.id
                        Button {
                            withAnimation(DS.Anim.quick) { vm.select(t) }
                        } label: {
                            VStack(spacing: DS.Spacing.xs) {
                                Image(systemName: t.icon)
                                    .font(DS.Font.scaled(18, weight: .semibold))
                                Text(t.title)
                                    .font(DS.Font.plex(13, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                            .frame(width: 104, height: 84)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .fill(on ? AnyShapeStyle(DS.Color.gradientPrimary) : AnyShapeStyle(DS.Color.cardBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                    .stroke(on ? Color.clear : DS.Color.cardBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: النموذج

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("النموذج", "Design"), icon: "rectangle.on.rectangle")
            HStack(spacing: DS.Spacing.sm) {
                ForEach(OccasionModel.allCases) { m in
                    modelCard(m)
                }
            }
        }
    }

    private func modelCard(_ m: OccasionModel) -> some View {
        let on = vm.effectiveModel == m
        return Button {
            withAnimation(DS.Anim.quick) { vm.model = m }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                // دائرة فوق (١) أو سداسي (٢) — نفس رسمة الموقع
                Image(systemName: m == .m1 ? "circle.circle" : "hexagon")
                    .font(DS.Font.scaled(20, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.title)
                        .font(DS.Font.plex(15, weight: .bold))
                    // القالب أو النسخة اللي ما فيها صورة (مشاركة العزاء، الوفاة بدون صورة، «بدون صورة») يقول «بدون صورة»
                    Text(vm.showsPhoto ? m.subtitle : L10n.t("بدون صورة", "No photo"))
                        .font(DS.Font.plex(12))
                        .opacity(0.8)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .fill(on ? AnyShapeStyle(DS.Color.gradientPrimary) : AnyShapeStyle(DS.Color.cardBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(on ? Color.clear : DS.Color.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: مكان النشر

    private var placementSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("مكان النشر", "Where to post"), icon: "paperplane.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DS.Spacing.sm)], spacing: DS.Spacing.sm) {
                ForEach(vm.placements) { p in
                    let on = p.id == vm.placement.id
                    Button {
                        withAnimation(DS.Anim.quick) { vm.placement = p }
                    } label: {
                        Text(p.title)
                            .font(DS.Font.plex(13, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundColor(on ? DS.Color.textOnPrimary : DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, DS.Spacing.sm)
                            .background(
                                Capsule().fill(on ? AnyShapeStyle(DS.Color.primary) : AnyShapeStyle(DS.Color.cardBackground))
                            )
                            .overlay(Capsule().stroke(on ? Color.clear : DS.Color.cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if vm.size == .story {
                Text(L10n.t("الستوري فيه هوامش أمان فوق وتحت حتى ما تغطيها أزرار التطبيقات.",
                            "Stories keep safe margins at the top and bottom so app buttons don't cover the content."))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
    }

    // MARK: التفاصيل (اختيارات)

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("التفاصيل", "Details"), icon: "checklist")
            HStack(spacing: DS.Spacing.sm) {
                Text(L10n.t("اختر من القوائم — والكتابة متاحة من «نص آخر»", "Pick from the lists — use “Other” to type"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
                Spacer(minLength: 0)
                Button(L10n.t("بدء من جديد", "Start over")) {
                    withAnimation(DS.Anim.quick) { vm.resetForm() }
                }
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.primary)
            }
            switch vm.template.kind {
            case .happy: happyForm
            case .death, .deathText: deathForm
            case .solace: solaceForm
            }
        }
    }

    private func genderChips(_ labels: [String]) -> some View {
        OccasionChips(options: labels, selected: vm.gender == .male ? 0 : 1) { i in
            withAnimation(DS.Anim.quick) { vm.setGender(i == 0 ? .male : .female) }
        }
    }

    private func toggle(_ key: String) -> Binding<Bool> {
        Binding(get: { vm.sel(key) == 1 },
                set: { on in withAnimation(DS.Anim.quick) { vm.setSel(key, on ? 1 : 0) } })
    }

    // MARK: الاسم (من الشجرة أو كتابة)

    private func nameSection(_ title: String) -> some View {
        OccasionFormCard(title: title, hint: L10n.t("سطر واحد — إذا طال ينختصر تلقائياً", "One line — shortened automatically if long")) {
            if let m = vm.member {
                selectedMember(m)
            } else {
                if vm.gender == .male && !vm.family.isEmpty {
                    Button {
                        showMemberPicker = true
                    } label: {
                        Label(L10n.t("اختر من شجرة العائلة", "Pick from the family tree"), systemImage: "magnifyingglass")
                            .font(DS.Font.calloutBold)
                            .foregroundColor(DS.Color.textOnPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Capsule().fill(DS.Color.primary))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
                OccasionTextInput(
                    text: vm.text("nameTyped"),
                    placeholder: vm.gender == .male && !vm.family.isEmpty
                        ? L10n.t("أو اكتب الاسم هنا", "Or type the name here")
                        : L10n.t("اكتب الاسم", "Type the name")
                )
            }
            if vm.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                OccasionRequiredHint(L10n.t("مطلوب — اختر الاسم من الشجرة أو اكتبه", "Required — pick the name from the tree or type it"))
            } else {
                formatPicker("name")
            }
        }
    }

    /// صيغة عنصر اسم (سداسي … ثلاثي) — تظهر لما يكون فيه أكثر من صيغة
    @ViewBuilder
    private func formatPicker(_ key: String) -> some View {
        if let r = vm.nameResolution(key) {
            OccasionNameFormatPicker(resolution: r) { n in
                withAnimation(DS.Anim.quick) { vm.setNameCount(key, n) }
            }
        }
    }

    private func selectedMember(_ m: FamilyMember) -> some View {
        HStack(spacing: DS.Spacing.md) {
            OccasionMemberAvatar(member: m, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.nameResolution("name")?.option.name ?? vm.name)
                    .font(DS.Font.calloutBold)
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
                .font(DS.Font.caption2)
                .foregroundColor(DS.Color.textTertiary)
            }
            Spacer(minLength: 0)
            Button(L10n.t("تغيير", "Change")) { showMemberPicker = true }
                .font(DS.Font.calloutBold)
                .foregroundColor(DS.Color.primary)
            Button {
                withAnimation(DS.Anim.quick) { vm.clearMember() }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Font.scaled(18))
                    .foregroundColor(DS.Color.textTertiary)
            }
            .accessibilityLabel(L10n.t("إلغاء الاختيار", "Clear selection"))
        }
        .padding(DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.primary.opacity(0.08))
        )
    }

    // MARK: التهاني

    private var happyForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            happyRecipient
            happyGreeting
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

    private var happyRecipient: some View {
        OccasionFormCard(title: L10n.t("لمن التهنئة", "Congratulating")) {
            genderChips([L10n.t("له", "Him"), L10n.t("لها", "Her")])
            OccasionChips(options: OccasionChoices.honorifics(vm.gender), selected: vm.sel("honor")) { vm.setSel("honor", $0) }
        }
    }

    private var happyGreeting: some View {
        let honors = OccasionChoices.honorifics(vm.gender)
        let honor = honors.indices.contains(vm.sel("honor")) ? honors[vm.sel("honor")] : honors[0]
        let openings = OccasionChoices.openings(vm.template.id).map { OccasionChoices.composeIntro($0, honor: honor) }
        return OccasionFormCard(title: L10n.t("صيغة التهنئة", "Greeting")) {
            OccasionChips(
                options: openings,
                selected: vm.sel("opening"),
                onSelect: { vm.setSel("opening", $0) },
                custom: OccasionCustomOption(text: vm.text("introCustom"), placeholder: L10n.t("اكتب سطر التهنئة", "Type the greeting line"))
            )
        }
    }

    private var graduationCard: some View {
        OccasionFormCard(title: L10n.t("التخرج", "Graduation")) {
            OccasionFieldLabel(L10n.t("المرحلة", "Degree"))
            OccasionChips(options: OccasionChoices.degrees, selected: vm.sel("degree")) { vm.setSel("degree", $0) }
            if vm.sel("degree") > 0 {
                OccasionFieldLabel(L10n.t("الجهة", "Institution"))
                OccasionChips(
                    options: OccasionChoices.institutions,
                    selected: vm.sel("inst"),
                    onSelect: { vm.setSel("inst", $0) },
                    custom: OccasionCustomOption(text: vm.text("instCustom"),
                                                 placeholder: L10n.t("اسم الجامعة أو الكلية", "University or college"),
                                                 label: L10n.t("جهة أخرى", "Other"))
                )
            }
        }
    }

    private var occasionCard: some View {
        OccasionFormCard(title: L10n.t("المناسبة", "Occasion")) {
            OccasionChips(
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
                OccasionRequiredHint(isBoy ? L10n.t("مطلوب — اكتب اسم المولود", "Required — type the baby's name")
                                           : L10n.t("مطلوب — اكتب اسم المولودة", "Required — type the baby's name"))
            }
        }
    }

    private func duaCard(_ options: [String]) -> some View {
        OccasionFormCard(title: L10n.t("الدعاء", "Prayer")) {
            OccasionTextCards(
                options: options,
                selected: vm.sel("dua"),
                onSelect: { vm.setSel("dua", $0) },
                noneLabel: L10n.t("بدون دعاء", "No prayer"),
                custom: OccasionCustomOption(text: vm.text("duaCustom"), placeholder: L10n.t("اكتب الدعاء", "Type the prayer"))
            )
        }
    }

    // MARK: إعلان الوفاة (مع صورة / بدون صورة)

    private var deathForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            deceasedCard
            nameSection(vm.gender == .male ? L10n.t("اسم الفقيد", "Name of the deceased") : L10n.t("اسم الفقيدة", "Name of the deceased"))
            if vm.template.kind == .death {
                OccasionFormCard(title: L10n.t("صلة القرابة", "Relation"), hint: L10n.t("اتركها فاضية لتختفي", "Leave empty to hide")) {
                    OccasionQuickText(text: vm.text("relation"), suggestions: vm.relationSuggestions,
                                      placeholder: L10n.t("مثال: والد كل من: علي، حسين", "e.g. والد كل من: علي، حسين"))
                    formatPicker("relation")
                }
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

    private var deceasedCard: some View {
        let g = vm.gender
        return OccasionFormCard(title: L10n.t("الفقيد", "The deceased")) {
            genderChips([L10n.t("فقيد", "Male"), L10n.t("فقيدة", "Female")])
            OccasionFieldLabel(L10n.t("السطر الأول", "First line"))
            OccasionChips(
                options: OccasionChoices.deathLeads(g),
                selected: vm.sel("lead"),
                onSelect: { vm.setSel("lead", $0) },
                custom: OccasionCustomOption(text: vm.text("leadCustom"))
            )
            OccasionFieldLabel(L10n.t("اللقب", "Title"))
            OccasionChips(
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
            formatPicker("rel1")
            OccasionFieldLabel(L10n.t("الأبناء", "Children"))
            OccasionQuickText(text: vm.text("rel2"), suggestions: vm.sonsSuggestion,
                              placeholder: male ? "والد كل من: الأسماء" : "والدة كل من: الأسماء")
            formatPicker("rel2")
            OccasionFieldLabel(L10n.t("الإخوان", "Brothers"))
            OccasionQuickText(text: vm.text("rel3"), suggestions: vm.brothersSuggestion,
                              placeholder: male ? "شقيق كل من: الأسماء" : "شقيقة كل من: الأسماء")
            formatPicker("rel3")
        }
    }

    private var funeralCard: some View {
        OccasionFormCard(title: L10n.t("التشييع", "Funeral"), toggle: toggle("funeral")) {
            OccasionFieldLabel(L10n.t("اليوم", "Day"))
            OccasionChips(options: OccasionChoices.funeralDays, selected: vm.sel("fDay")) { vm.setSel("fDay", $0) }
            OccasionFieldLabel(L10n.t("الوقت", "Time"))
            OccasionChips(options: OccasionChoices.funeralTimes, selected: vm.sel("fTime")) { vm.setSel("fTime", $0) }
            OccasionFieldLabel(L10n.t("المقبرة", "Cemetery"))
            OccasionChips(
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
                .tint(DS.Color.primary)
            OccasionFieldLabel(L10n.t("المدة", "Duration"))
            OccasionChips(options: OccasionChoices.durationLabels, selected: vm.sel("dur")) { vm.setSel("dur", $0) }
        }
    }

    private func venueCard(_ side: String) -> some View {
        OccasionFormCard(
            title: side == "men" ? L10n.t("عزاء الرجال", "Men's condolences") : L10n.t("عزاء النساء", "Women's condolences"),
            toggle: toggle(side)
        ) {
            OccasionFieldLabel(L10n.t("المكان", "Place"))
            OccasionHusseiniyaMenu(
                place: vm.form.txt("\(side)Place"),
                onPick: { h in withAnimation(DS.Anim.quick) { vm.setVenuePlace(side, h.name) } },
                onOther: { withAnimation(DS.Anim.quick) { vm.pickOtherHusseiniya(side) } }
            )
            OccasionQuickText(
                text: vm.venuePlace(side),
                suggestions: vm.diwaniyas.map(\.title) + OccasionChoices.venuePresets(vm.gender),
                placeholder: L10n.t("ديوان العائلة (إذا تركته فاضي)", "Family diwaniya (if left empty)")
            )
            OccasionFieldLabel(L10n.t("المنطقة", "Area"))
            OccasionAreaField(text: vm.text("\(side)Area"))
            OccasionFieldLabel(L10n.t("الأوقات", "Times"))
            OccasionChips(options: OccasionChoices.venueTimeLabels, selected: vm.sel("\(side)Times")) {
                vm.setSel("\(side)Times", $0)
            }
        }
    }

    private var deathDuaCard: some View {
        let options = OccasionChoices.deathDuas(vm.gender).map { pair in
            [pair.0, pair.1].filter { !$0.isEmpty }.joined(separator: " — ")
        }
        return OccasionFormCard(title: L10n.t("الدعاء", "Prayer")) {
            OccasionTextCards(
                options: options,
                selected: vm.sel("deathDua"),
                onSelect: { vm.setSel("deathDua", $0) },
                noneLabel: L10n.t("بدون دعاء", "No prayer"),
                custom: OccasionCustomOption(text: vm.text("dua1Custom"), placeholder: L10n.t("اكتب الدعاء", "Type the prayer"))
            )
        }
    }

    // MARK: مشاركة العزاء

    private var solaceForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            OccasionFormCard(title: L10n.t("من", "From")) {
                OccasionChips(
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
                    OccasionRequiredHint(L10n.t("مطلوب — اكتب اسم العائلة", "Required — type the family name"))
                } else {
                    formatPicker("to")
                }
                OccasionFieldLabel(L10n.t("الصيغة", "Wording"))
                OccasionChips(
                    options: OccasionChoices.solaceToFormats.map { $0.replacingOccurrences(of: "{x}", with: "…") },
                    selected: vm.sel("toFmt")
                ) { vm.setSel("toFmt", $0) }
            }
            OccasionFormCard(title: L10n.t("الفقيد", "The deceased")) {
                genderChips([L10n.t("فقيد", "Male"), L10n.t("فقيدة", "Female")])
                OccasionChips(
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
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("الصورة", "Photo"), icon: "photo.fill")
            if vm.template.photoOptional {
                OccasionChips(options: [L10n.t("مع صورة", "With photo"), L10n.t("بدون صورة", "No photo")],
                              selected: vm.withPhoto ? 0 : 1) { i in
                    withAnimation(DS.Anim.quick) { vm.withPhoto = i == 0 }
                }
                if !vm.showsPhoto {
                    Text(L10n.t("مكان الصورة يروح للآية والاسم — بخط أكبر.", "The photo's space goes to the verse and the name, in larger type."))
                        .font(DS.Font.caption1)
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            if vm.showsPhoto {
                photoControls
            }
        }
    }

    /// اختيار الصورة وضبطها (تظهر لما يكون في البوست صورة)
    private var photoControls: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.md) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label(vm.photo.image == nil ? L10n.t("اختيار صورة", "Choose photo") : L10n.t("تغيير الصورة", "Change photo"),
                          systemImage: "photo.on.rectangle")
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.textOnPrimary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, DS.Spacing.sm + 2)
                        .background(Capsule().fill(DS.Color.primary))
                }
                if vm.photo.image != nil {
                    Button(L10n.t("إزالة", "Remove")) {
                        vm.removePhoto()
                        pickerItem = nil
                    }
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.error)
                }
                Spacer(minLength: 0)
            }
            if vm.photoFromMember {
                Label(L10n.t("صورة العضو من شجرة العائلة — تقدر تغيّرها", "The member's photo from the family tree — you can change it"),
                      systemImage: "checkmark.circle.fill")
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.success)
            }
            Toggle(L10n.t("أبيض وأسود", "Black & white"), isOn: $vm.photo.gray)
                .font(DS.Font.callout)
                .tint(DS.Color.primary)
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
                .tint(DS.Color.primary)
        }
    }

    // MARK: الحفظ والمشاركة

    private var actions: some View {
        VStack(spacing: DS.Spacing.md) {
            DSPrimaryButton(L10n.t("حفظ في الصور", "Save to Photos"), icon: "square.and.arrow.down", isLoading: vm.isWorking) {
                Task { await vm.saveToPhotos() }
            }
            .opacity(vm.missing.isEmpty ? 1 : 0.5)
            DSSecondaryButton(L10n.t("مشاركة", "Share"), icon: "square.and.arrow.up", color: DS.Color.primary) {
                Task { await vm.share() }
            }
            .disabled(vm.isWorking)
            .opacity(vm.missing.isEmpty ? 1 : 0.5)
            if !vm.missing.isEmpty {
                OccasionRequiredHint(L10n.t("قبل الحفظ أكمل: ", "Before saving, fill in: ") + vm.missing.joined(separator: "، "))
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
