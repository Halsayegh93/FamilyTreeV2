import SwiftUI
import PhotosUI
import Photos

struct EditNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @Environment(\.dismiss) var dismiss

    let news: NewsPost
    @State private var content: String
    @State private var selectedType: String
    @State private var existingImageURLs: [String]
    @State private var selectedImages: [UIImage] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false
    @State private var pollQuestion: String
    @State private var pollOption1: String
    @State private var pollOption2: String
    @State private var pollOption3: String
    @State private var pollOption4: String
    @State private var showEditErrorAlert = false
    @State private var isSubmitting = false

    init(news: NewsPost) {
        self.news = news
        _content = State(initialValue: news.content)
        _selectedType = State(initialValue: news.type)
        _existingImageURLs = State(initialValue: news.mediaURLs)
        _pollQuestion = State(initialValue: news.poll_question ?? "")

        let options = news.poll_options ?? []
        _pollOption1 = State(initialValue: options.indices.contains(0) ? options[0] : "")
        _pollOption2 = State(initialValue: options.indices.contains(1) ? options[1] : "")
        _pollOption3 = State(initialValue: options.indices.contains(2) ? options[2] : "")
        _pollOption4 = State(initialValue: options.indices.contains(3) ? options[3] : "")
    }

    private var normalizedPollOptions: [String] {
        [pollOption1, pollOption2, pollOption3, pollOption4]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var isPollValid: Bool {
        selectedType != "تصويت" || normalizedPollOptions.count >= 2
    }

    private var isPoll: Bool { selectedType == "تصويت" }

    private var canSubmit: Bool {
        if isPoll {
            return isPollValid && !isSubmitting
        } else {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.lg) {
                    editTypeSelector

                    if isPoll {
                        editPollSection
                    } else {
                        editContentSection
                    }

                    editSubmitSection
                }
                .animation(DS.Anim.snappy, value: isPoll)
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.top, DS.Spacing.sm)
                .padding(.bottom, DS.Spacing.xxxl)
            }
            .background(.ultraThinMaterial)
            .navigationTitle(L10n.t("تعديل الخبر", "Edit Post"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.t("إلغاء", "Cancel")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.error)
                }
            }
            .alert(L10n.t("تعذر التعديل", "Edit Failed"), isPresented: $showEditErrorAlert) {
                Button(L10n.t("حسناً", "OK"), role: .cancel) {}
            } message: { Text(newsVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء تعديل الخبر.", "An error occurred while updating.")) }
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                loadImages(from: items)
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    // MARK: - Type Selector
    private var editTypeSelector: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("نوع الخبر", "Post Type"),
                icon: "tag.fill",
                iconColor: DS.Color.primary
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.sm) {
                    ForEach(NewsTypeHelper.mainTypes, id: \.self) { type in
                        let isSelected = selectedType == type
                        let typeColor = NewsTypeHelper.color(for: type)

                        Button(action: {
                            withAnimation(DS.Anim.snappy) { selectedType = type }
                        }) {
                            HStack(spacing: DS.Spacing.sm) {
                                Image(systemName: NewsTypeHelper.icon(for: type))
                                    .font(DS.Font.scaled(14, weight: .semibold))
                                    .foregroundColor(isSelected ? DS.Color.textOnPrimary : typeColor)
                                    .frame(width: 28, height: 28)
                                    .background(isSelected ? typeColor : typeColor.opacity(0.12))
                                    .clipShape(Circle())

                                Text(NewsTypeHelper.displayName(for: type))
                                    .font(DS.Font.scaled(13, weight: .bold))
                                    .foregroundColor(isSelected ? typeColor : DS.Color.textSecondary)
                            }
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.vertical, DS.Spacing.xs)
                            .background(
                                Capsule()
                                    .fill(isSelected ? typeColor.opacity(0.1) : DS.Color.surface.opacity(0.5))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(isSelected ? typeColor.opacity(0.4) : DS.Color.primary.opacity(0.08), lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(DSBoldButtonStyle())
                    }
                }
                .padding(.horizontal, DS.Spacing.md)
            }
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Content Section (مع شريط الأدوات والصور)
    private var editContentSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("محتوى الخبر", "Post Content"),
                icon: "text.alignright",
                iconColor: DS.Color.accent
            )

            // حقل النص
            ZStack(alignment: .topTrailing) {
                TextEditor(text: $content)
                    .frame(minHeight: 60, maxHeight: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollContentBackground(.hidden)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textPrimary)
                    .padding(DS.Spacing.sm)

                if content.isEmpty {
                    Text(L10n.t("اكتب الخبر هنا...", "Write your post here..."))
                        .font(DS.Font.callout)
                        .foregroundColor(DS.Color.textTertiary)
                        .padding(.top, DS.Spacing.md)
                        .padding(.trailing, DS.Spacing.md)
                        .allowsHitTesting(false)
                }
            }

            // الصور الحالية والجديدة
            if !existingImageURLs.isEmpty || !selectedImages.isEmpty {
                photosPreview
            }

            // شريط الأدوات (أيقونة الصور)
            contentToolbar
        }
    }

    // MARK: - Content Toolbar
    private var contentToolbar: some View {
        let totalPhotos = existingImageURLs.count + selectedImages.count
        return HStack(spacing: DS.Spacing.md) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: max(1, 5 - existingImageURLs.count),
                matching: .images
            ) {
                HStack(spacing: DS.Spacing.xs) {
                    if isLoadingPhotos {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(DS.Color.primary)
                    } else {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(DS.Font.scaled(16, weight: .medium))
                    }

                    if totalPhotos > 0 {
                        Text("\(totalPhotos)/5")
                            .font(DS.Font.caption2)
                            .fontWeight(.bold)
                    }
                }
                .foregroundColor(DS.Color.primary)
                .padding(.horizontal, DS.Spacing.md)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.primary.opacity(0.06))
                .clipShape(Capsule())
            }
            .disabled(isLoadingPhotos || totalPhotos >= 5)

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.md)
    }

    // MARK: - Photos Preview
    private var photosPreview: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                // الصور الموجودة (URLs)
                ForEach(Array(existingImageURLs.enumerated()), id: \.offset) { idx, url in
                    ZStack(alignment: .topTrailing) {
                        CachedAsyncImage(url: URL(string: url)) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            ZStack {
                                DS.Color.surface
                                ProgressView().tint(DS.Color.primary).scaleEffect(0.7)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            withAnimation(DS.Anim.snappy) {
                                existingImageURLs.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundStyle(.white, DS.Color.error)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        }
                        .offset(x: 6, y: -6)
                    }
                }

                // الصور الجديدة (UIImage)
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))

                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            withAnimation(DS.Anim.snappy) {
                                selectedImages.remove(at: idx)
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(DS.Font.scaled(18, weight: .bold))
                                .foregroundStyle(.white, DS.Color.error)
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    // MARK: - Poll Section
    private var editPollSection: some View {
        DSCard(padding: 0) {
            DSSectionHeader(
                title: L10n.t("خيارات التصويت", "Poll Options"),
                icon: "chart.bar.fill",
                iconColor: DS.Color.newsVote
            )

            VStack(spacing: DS.Spacing.sm) {
                pollField(placeholder: L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $pollQuestion, icon: "questionmark.circle")
                pollField(placeholder: L10n.t("الخيار الأول", "Option 1"), text: $pollOption1, icon: "1.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثاني", "Option 2"), text: $pollOption2, icon: "2.circle.fill")
                pollField(placeholder: L10n.t("الخيار الثالث (اختياري)", "Option 3 (optional)"), text: $pollOption3, icon: "3.circle.fill")
                pollField(placeholder: L10n.t("الخيار الرابع (اختياري)", "Option 4 (optional)"), text: $pollOption4, icon: "4.circle.fill")
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.md)
        }
    }

    // MARK: - Submit Section
    private var editSubmitSection: some View {
        DSPrimaryButton(
            L10n.t("حفظ التعديلات", "Save Changes"),
            icon: "checkmark.circle.fill",
            isLoading: isSubmitting,
            useGradient: canSubmit,
            color: canSubmit ? DS.Color.primary : .gray
        ) {
            Task { await submitEdits() }
        }
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1.0 : 0.6)
    }

    private func pollField(placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(DS.Font.scaled(14, weight: .medium))
                .foregroundColor(DS.Color.newsVote)
                .frame(width: 24)

            TextField(placeholder, text: text)
                .font(DS.Font.callout)
                .foregroundColor(DS.Color.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.textTertiary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Load Images
    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            isLoadingPhotos = true
            var loaded: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    loaded.append(image)
                }
            }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            withAnimation(DS.Anim.snappy) {
                selectedImages = loaded
                isLoadingPhotos = false
            }
        }
    }

    // MARK: - Submit
    private func submitEdits() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        let question = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)

        var imageURLs: [String] = []
        let finalContent: String

        if isPoll {
            finalContent = L10n.t("تصويت", "Poll")
        } else {
            finalContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
            imageURLs = existingImageURLs
            if let authorId = authVM.currentUser?.id {
                for image in selectedImages {
                    if let url = await newsVM.uploadNewsImage(image: image, for: authorId) {
                        imageURLs.append(url)
                    }
                }
            }
        }

        let isUpdated = await newsVM.updateNewsPost(
            postId: news.id,
            content: finalContent,
            type: selectedType,
            imageURLs: imageURLs,
            pollQuestion: isPoll && !question.isEmpty ? question : nil,
            pollOptions: isPoll ? normalizedPollOptions : []
        )

        if isUpdated { dismiss() } else { showEditErrorAlert = true }
    }
}
