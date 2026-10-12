import SwiftUI
import UIKit
import PhotosUI

/// بوستات المناسبات — للإدارة والمشرفين (canModerate).
/// اختيار القالب ومكان النشر (يحدد المقاس)، تعبئة النصوص، اختيار الصورة، ثم حفظ في الصور أو مشاركة.
struct OccasionComposerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var vm = OccasionComposerViewModel()
    @ObservedObject private var kit = OccasionKit.shared
    @State private var pickerItem: PhotosPickerItem?

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
        .onChange(of: pickerItem) { item in
            Task { await vm.loadPhoto(item) }
        }
        .sheet(item: $vm.shareItem) { item in
            OccasionShareSheet(items: [item.url])
        }
        .alert(vm.message ?? "", isPresented: Binding(
            get: { vm.message != nil },
            set: { if !$0 { vm.message = nil } }
        )) {
            Button(L10n.t("حسناً", "OK"), role: .cancel) {}
        }
    }

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
                preview
                templateSection
                placementSection
                detailsSection
                if vm.template.hasPhoto { photoSection }
                actions
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Color.background.ignoresSafeArea())
    }

    // MARK: المعاينة

    private var preview: some View {
        let canvas = vm.size.canvas
        return VStack(spacing: DS.Spacing.sm) {
            GeometryReader { geo in
                let scale = geo.size.width / canvas.width
                OccasionPostView(template: vm.template, size: vm.size, values: vm.values, photo: vm.photo,
                                 kit: kit, revision: kit.revision)
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

    // MARK: البيانات

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("البيانات", "Details"), icon: "text.alignright")
            HStack(spacing: DS.Spacing.md) {
                Picker(L10n.t("صيغة النص", "Wording"), selection: Binding(get: { vm.gender }, set: { vm.setGender($0) })) {
                    ForEach(OccasionGender.allCases) { g in
                        Text(g.title).tag(g)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                Spacer(minLength: 0)
                Button(L10n.t("رجوع للنص الأصلي", "Reset text")) {
                    withAnimation(DS.Anim.quick) { vm.resetTexts() }
                }
                .font(DS.Font.caption1)
                .foregroundColor(DS.Color.primary)
            }
            ForEach(fieldGroups, id: \.id) { group in
                if let title = group.title {
                    DSCard(padding: DS.Spacing.md) {
                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text(title)
                                .font(DS.Font.headline)
                                .foregroundColor(DS.Color.textPrimary)
                            ForEach(group.fields) { field in fieldEditor(field) }
                        }
                    }
                } else {
                    ForEach(group.fields) { field in fieldEditor(field) }
                }
            }
        }
    }

    private struct FieldGroup {
        let id: Int
        let title: String?
        var fields: [OccasionField]
    }

    private var fieldGroups: [FieldGroup] {
        var groups: [FieldGroup] = []
        for field in vm.template.fields {
            if let last = groups.last, last.title == field.group {
                groups[groups.count - 1].fields.append(field)
            } else {
                groups.append(FieldGroup(id: groups.count, title: field.group, fields: [field]))
            }
        }
        return groups
    }

    private func fieldEditor(_ field: OccasionField) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.xs) {
                Text(field.label)
                    .foregroundColor(DS.Color.textSecondary)
                if field.optional {
                    Text(L10n.t("— اتركه فاضي ليختفي", "— leave empty to hide"))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
            .font(DS.Font.caption1)
            TextField("", text: vm.binding(for: field.key), axis: .vertical)
                .lineLimit(field.multiline ? 2...5 : 1...3)
                .font(DS.Font.body)
                .foregroundColor(DS.Color.textPrimary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm + 2)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.cardBorder, lineWidth: 1)
                )
        }
    }

    // MARK: الصورة

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(title: L10n.t("الصورة", "Photo"), icon: "photo.fill")
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
            DSSecondaryButton(L10n.t("مشاركة", "Share"), icon: "square.and.arrow.up", color: DS.Color.primary) {
                Task { await vm.share() }
            }
            .disabled(vm.isWorking)
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
