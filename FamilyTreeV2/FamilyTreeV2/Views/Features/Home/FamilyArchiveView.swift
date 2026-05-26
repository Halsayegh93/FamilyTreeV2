import SwiftUI
import PDFKit
import PhotosUI
import UniformTypeIdentifiers

/// شاشة أرشيف العائلة — وثائق وكتب وصور قديمة. الكل يقدر يتصفّح ويُحمّل،
/// الرفع/الحذف للمدراء فقط (owner + admin).
struct FamilyArchiveView: View {
    @EnvironmentObject private var authVM: AuthViewModel
    @StateObject private var archiveVM = FamilyArchiveViewModel()

    @State private var selectedCategory: ArchiveItem.Category = .documents
    @State private var showingUpload = false
    @State private var selectedItem: ArchiveItem? = nil
    @State private var itemToDelete: ArchiveItem? = nil

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: DS.Spacing.sm),
        GridItem(.flexible(), spacing: DS.Spacing.sm)
    ]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                categoryPicker
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.top, DS.Spacing.sm)
                    .padding(.bottom, DS.Spacing.xs)

                if archiveVM.isLoading && archiveVM.items.isEmpty {
                    Spacer()
                    ProgressView().tint(DS.Color.primary)
                    Spacer()
                } else if archiveVM.items(in: selectedCategory).isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: gridColumns, spacing: DS.Spacing.sm) {
                            ForEach(archiveVM.items(in: selectedCategory)) { item in
                                Button { selectedItem = item } label: {
                                    archiveCard(item)
                                }
                                .buttonStyle(DSScaleButtonStyle())
                                .contextMenu {
                                    if authVM.isAdmin {
                                        Button {
                                            Task { await archiveVM.toggleHidden(item) }
                                        } label: {
                                            Label(
                                                item.isHidden
                                                    ? L10n.t("إظهار للجميع", "Show to all")
                                                    : L10n.t("إخفاء من الأعضاء", "Hide from members"),
                                                systemImage: item.isHidden ? "eye.fill" : "eye.slash.fill"
                                            )
                                        }
                                        Button(role: .destructive) {
                                            itemToDelete = item
                                        } label: {
                                            Label(L10n.t("حذف", "Delete"), systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.bottom, DS.Spacing.xxxxl)
                    }
                    .refreshable { await archiveVM.fetchItems() }
                }
            }

            // زر رفع — للمدراء فقط
            if authVM.isAdmin {
                DSFloatingButton(icon: "plus") {
                    showingUpload = true
                }
                .padding(.trailing, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.lg)
            }
        }
        .task {
            archiveVM.configure(authVM: authVM)
            await archiveVM.fetchItems()
        }
        .sheet(isPresented: $showingUpload) {
            ArchiveUploadSheet(archiveVM: archiveVM, defaultCategory: selectedCategory)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedItem) { item in
            ArchiveItemViewer(item: item)
        }
        .alert(L10n.t("حذف من الأرشيف", "Delete from archive"),
               isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
               )) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) {
                if let item = itemToDelete {
                    Task { await archiveVM.deleteItem(item) }
                }
                itemToDelete = nil
            }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) { itemToDelete = nil }
        } message: {
            Text(L10n.t("حذف هذا العنصر نهائياً من الأرشيف؟",
                       "Permanently delete this item from the archive?"))
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(ArchiveItem.Category.allCases) { category in
                    categoryChip(category)
                }
            }
        }
    }

    private func categoryChip(_ category: ArchiveItem.Category) -> some View {
        let isActive = selectedCategory == category
        let count = archiveVM.count(in: category)
        return Button {
            withAnimation(DS.Anim.snappy) { selectedCategory = category }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(DS.Font.scaled(12, weight: .bold))
                Text(L10n.t(category.displayName, category.displayNameEn))
                    .font(DS.Font.scaled(13, weight: isActive ? .bold : .semibold))
                if count > 0 {
                    Text("\(count)")
                        .font(DS.Font.scaled(11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(isActive ? Color.white.opacity(0.25) : DS.Color.primary.opacity(0.15))
                        )
                }
            }
            .foregroundColor(isActive ? .white : DS.Color.primary)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(isActive ? DS.Color.primary : DS.Color.primary.opacity(0.10))
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Archive Card

    private func archiveCard(_ item: ArchiveItem) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            // معاينة بصرية أو أيقونة
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.08))

                    if item.isImage, let url = URL(string: item.fileUrl) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ProgressView().tint(DS.Color.primary)
                        }
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: item.isPDF ? "doc.text.fill" : item.category.iconName)
                                .font(.system(size: 36, weight: .light))
                                .foregroundColor(DS.Color.primary.opacity(0.85))
                            if item.isPDF {
                                Text("PDF")
                                    .font(DS.Font.scaled(10, weight: .black))
                                    .foregroundColor(DS.Color.primary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(DS.Color.primary.opacity(0.15)))
                            }
                        }
                    }
                }
                .frame(height: 130)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                // شارة "مخفي" — تظهر فقط للإدارة (الأعضاء العاديون لا يجلبون العنصر أصلاً)
                if item.isHidden {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.slash.fill")
                            .font(DS.Font.scaled(9, weight: .bold))
                        Text(L10n.t("مخفي", "Hidden"))
                            .font(DS.Font.scaled(9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(DS.Color.warning))
                    .padding(6)
                }
            }

            // عنوان + حجم
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(DS.Font.scaled(13, weight: .bold))
                    .foregroundColor(DS.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.formattedSize.isEmpty {
                    Text(item.formattedSize)
                        .font(DS.Font.scaled(10, weight: .medium))
                        .foregroundColor(DS.Color.textTertiary)
                }
            }
        }
        .padding(DS.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .fill(DS.Color.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(item.isHidden ? DS.Color.warning.opacity(0.30) : DS.Color.primary.opacity(0.08), lineWidth: 1)
        )
        .opacity(item.isHidden ? 0.75 : 1.0)
        .dsSubtleShadow()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: selectedCategory.iconName)
                .font(.system(size: 56, weight: .light))
                .foregroundColor(DS.Color.textTertiary)
            Text(L10n.t("لا توجد عناصر في هذا القسم بعد",
                       "No items in this section yet"))
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
            if authVM.isAdmin {
                Text(L10n.t("اضغط + لإضافة عنصر",
                           "Tap + to add an item"))
                    .font(DS.Font.caption1)
                    .foregroundColor(DS.Color.textTertiary)
            }
        }
        .padding()
    }
}

// MARK: - Upload Sheet

/// شيت رفع عنصر للأرشيف — PDF أو صورة.
struct ArchiveUploadSheet: View {
    @ObservedObject var archiveVM: FamilyArchiveViewModel
    let defaultCategory: ArchiveItem.Category
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var category: ArchiveItem.Category
    @State private var pickedFileData: Data? = nil
    @State private var pickedFileName: String = ""
    @State private var pickedMimeType: String = ""
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var errorBanner: String? = nil

    init(archiveVM: FamilyArchiveViewModel, defaultCategory: ArchiveItem.Category) {
        self.archiveVM = archiveVM
        self.defaultCategory = defaultCategory
        self._category = State(initialValue: defaultCategory)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        pickedFileData != nil &&
        !archiveVM.isUploading
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {

                    // اختيار الملف
                    fileSelectionSection

                    // العنوان
                    fieldGroup(label: L10n.t("العنوان", "Title"), required: true) {
                        DSTextField(
                            label: "",
                            placeholder: L10n.t("مثلاً: شجرة العائلة 1965", "e.g. Family Tree 1965"),
                            text: $title,
                            icon: "textformat"
                        )
                    }

                    // الوصف
                    fieldGroup(label: L10n.t("الوصف (اختياري)", "Description (optional)")) {
                        DSTextField(
                            label: "",
                            placeholder: L10n.t("ملاحظات أو سياق", "Notes or context"),
                            text: $description,
                            icon: "text.alignleft"
                        )
                    }

                    // القسم
                    fieldGroup(label: L10n.t("القسم", "Category")) {
                        categorySegmented
                    }

                    if archiveVM.isUploading {
                        VStack(spacing: DS.Spacing.xs) {
                            ProgressView(value: archiveVM.uploadProgress)
                                .progressViewStyle(.linear)
                                .tint(DS.Color.primary)
                            Text(L10n.t("جاري الرفع...", "Uploading..."))
                                .font(DS.Font.caption1)
                                .foregroundColor(DS.Color.textSecondary)
                        }
                        .padding(.top, DS.Spacing.sm)
                    }

                    if let errorBanner {
                        Text(errorBanner)
                            .font(DS.Font.caption1)
                            .foregroundColor(DS.Color.error)
                            .padding(.top, DS.Spacing.xs)
                    }

                    Spacer(minLength: DS.Spacing.xxxl)
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.md)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle(L10n.t("إضافة للأرشيف", "Add to Archive"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .disabled(archiveVM.isUploading)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("رفع", "Upload")) { submit() }
                        .fontWeight(.bold)
                        .disabled(!canSubmit)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [UTType.pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $photoItem,
                matching: .images
            )
            .onChange(of: photoItem) { newItem in
                handlePhotoPick(newItem)
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - File Selection Section

    private var fileSelectionSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            if pickedFileData != nil {
                // عرض الملف المختار
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: pickedMimeType == "application/pdf" ? "doc.text.fill" : "photo.fill")
                        .font(DS.Font.scaled(20, weight: .bold))
                        .foregroundColor(DS.Color.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pickedFileName.isEmpty ? L10n.t("ملف مختار", "Selected file") : pickedFileName)
                            .font(DS.Font.callout)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                        Text(ByteCountFormatter().string(fromByteCount: Int64(pickedFileData?.count ?? 0)))
                            .font(DS.Font.caption2)
                            .foregroundColor(DS.Color.textSecondary)
                    }
                    Spacer()
                    Button {
                        pickedFileData = nil
                        pickedFileName = ""
                        pickedMimeType = ""
                        photoItem = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DS.Color.error)
                    }
                }
                .padding(DS.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1)
                )
            } else {
                // أزرار اختيار النوع
                HStack(spacing: DS.Spacing.sm) {
                    pickButton(
                        icon: "doc.text.fill",
                        title: L10n.t("ملف PDF", "PDF File")
                    ) { showFileImporter = true }

                    pickButton(
                        icon: "photo.fill",
                        title: L10n.t("صورة", "Photo")
                    ) { showPhotoPicker = true }
                }
            }
        }
    }

    private func pickButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(DS.Font.scaled(22, weight: .bold))
                    .foregroundColor(DS.Color.primary)
                Text(title)
                    .font(DS.Font.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Color.textPrimary)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(DS.Color.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .strokeBorder(DS.Color.primary.opacity(0.20), lineWidth: 1.5)
            )
        }
        .buttonStyle(DSScaleButtonStyle())
    }

    // MARK: - Category Segmented

    private var categorySegmented: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ArchiveItem.Category.allCases) { cat in
                    Button {
                        category = cat
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cat.iconName)
                                .font(DS.Font.scaled(11, weight: .bold))
                            Text(L10n.t(cat.displayName, cat.displayNameEn))
                                .font(DS.Font.scaled(12, weight: category == cat ? .bold : .medium))
                        }
                        .foregroundColor(category == cat ? .white : DS.Color.primary)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(category == cat ? DS.Color.primary : DS.Color.primary.opacity(0.10)))
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func fieldGroup<C: View>(label: String, required: Bool = false, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(label)
                    .font(DS.Font.scaled(12, weight: .semibold))
                    .foregroundColor(DS.Color.textSecondary)
                if required {
                    Text("*")
                        .font(DS.Font.scaled(12, weight: .bold))
                        .foregroundColor(DS.Color.error)
                }
            }
            content()
        }
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            // الوصول الآمن للملف
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            pickedFileData = data
            pickedFileName = url.lastPathComponent
            pickedMimeType = "application/pdf"
            if title.isEmpty {
                title = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            errorBanner = L10n.t("تعذّر قراءة الملف.", "Failed to read file.")
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                await MainActor.run {
                    pickedFileData = data
                    // نخمّن النوع — PhotosPicker يعطي JPEG/HEIC غالباً
                    let utType = item.supportedContentTypes.first
                    if utType?.conforms(to: .png) == true {
                        pickedMimeType = "image/png"
                        pickedFileName = "image.png"
                    } else if utType?.conforms(to: .heic) == true {
                        pickedMimeType = "image/heic"
                        pickedFileName = "image.heic"
                    } else {
                        pickedMimeType = "image/jpeg"
                        pickedFileName = "image.jpg"
                    }
                }
            } catch {
                await MainActor.run {
                    errorBanner = L10n.t("تعذّر تحميل الصورة.", "Failed to load image.")
                }
            }
        }
    }

    private func submit() {
        guard let data = pickedFileData else { return }
        Task {
            let item = await archiveVM.uploadItem(
                title: title,
                description: description,
                category: category,
                fileData: data,
                fileName: pickedFileName,
                mimeType: pickedMimeType
            )
            if item != nil {
                dismiss()
            } else if let err = archiveVM.errorMessage {
                errorBanner = err
            }
        }
    }
}

// MARK: - Archive Item Viewer

/// عارض عناصر الأرشيف — PDFKit لـ PDFs، CachedAsyncImage للصور.
/// زر مشاركة/تنزيل يفتح UIActivityViewController.
struct ArchiveItemViewer: View {
    let item: ArchiveItem
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var shareURL: URL? = nil
    @State private var downloading = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()

                if item.isPDF, let url = URL(string: item.fileUrl) {
                    ArchivePDFView(url: url)
                        .ignoresSafeArea(edges: .bottom)
                } else if item.isImage, let url = URL(string: item.fileUrl) {
                    ScrollView([.horizontal, .vertical], showsIndicators: false) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView().tint(DS.Color.primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                } else {
                    VStack(spacing: DS.Spacing.md) {
                        Image(systemName: "doc.questionmark")
                            .font(.system(size: 56))
                            .foregroundColor(DS.Color.textTertiary)
                        Text(L10n.t("لا يمكن عرض هذا الملف داخل التطبيق",
                                   "This file can't be previewed in the app"))
                            .font(DS.Font.callout)
                            .foregroundColor(DS.Color.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await downloadAndShare() }
                    } label: {
                        if downloading {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .disabled(downloading)
                }
            }
            .sheet(isPresented: $showShare) {
                if let url = shareURL {
                    ShareSheet(items: [url])
                }
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    /// تحميل الملف لمجلد مؤقت ثم فتح share sheet للحفظ في Files / مشاركة.
    private func downloadAndShare() async {
        guard let url = URL(string: item.fileUrl) else { return }
        downloading = true
        defer { downloading = false }
        do {
            let (tempURL, _) = try await URLSession.shared.download(from: url)
            // إعادة تسمية الملف ليحمل اسمه الأصلي
            let suggestedName = item.fileName ?? (item.title + (item.isPDF ? ".pdf" : ".jpg"))
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tempURL, to: dest)
            shareURL = dest
            showShare = true
        } catch {
            Log.error("[Archive] خطأ تنزيل: \(error.localizedDescription)")
        }
    }
}

// MARK: - PDF View (UIViewRepresentable)

/// عارض PDF بسيط مبني على PDFKit، يحمّل من URL.
private struct ArchivePDFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground

        Task.detached {
            if let data = try? Data(contentsOf: url),
               let doc = PDFDocument(data: data) {
                await MainActor.run {
                    view.document = doc
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
