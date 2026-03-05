import SwiftUI
import PhotosUI

struct EditNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @Environment(\.dismiss) var dismiss

    let news: NewsPost
    @State private var content: String
    @State private var selectedType: String
    @State private var existingImageURLs: [String]
    @State private var selectedImages: [UIImage] = []
    @State private var editPickerItems: [PhotosPickerItem] = []
    @State private var isLoadingEditImages = false
    @State private var pollQuestion: String
    @State private var pollOption1: String
    @State private var pollOption2: String
    @State private var pollOption3: String
    @State private var pollOption4: String
    @State private var showEditErrorAlert = false

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

    private var canSubmit: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isPollValid && !authVM.isLoading
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: DS.Spacing.md) {
                    DSCard(padding: 0) {
                        DSSectionHeader(
                            title: L10n.t("نوع الخبر", "Post Type"),
                            icon: "tag.fill",
                            iconColor: DS.Color.primary
                        )

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.sm), count: 3), spacing: DS.Spacing.sm) {
                            ForEach(NewsTypeHelper.allTypes, id: \.self) { type in
                                let isSelected = selectedType == type
                                let typeColor = NewsTypeHelper.color(for: type)

                                Button(action: {
                                    withAnimation(DS.Anim.snappy) { selectedType = type }
                                }) {
                                    VStack(spacing: DS.Spacing.xs) {
                                        ZStack {
                                            Circle()
                                                .fill(isSelected ? typeColor : typeColor.opacity(0.12))
                                                .frame(width: 42, height: 42)

                                            Image(systemName: NewsTypeHelper.icon(for: type))
                                                .font(DS.Font.scaled(16, weight: .semibold))
                                                .foregroundColor(isSelected ? .white : typeColor)
                                        }

                                        Text(NewsTypeHelper.displayName(for: type))
                                            .font(DS.Font.caption1)
                                            .fontWeight(.bold)
                                            .foregroundColor(isSelected ? typeColor : DS.Color.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, DS.Spacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                            .fill(isSelected ? typeColor.opacity(0.1) : Color.clear)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                            .stroke(isSelected ? typeColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(DSBoldButtonStyle())
                            }
                        }
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.bottom, DS.Spacing.md)
                    }

                    TextEditor(text: $content)
                        .frame(minHeight: 120, maxHeight: 150)
                        .padding(DS.Spacing.sm)
                        .background(DS.Color.surface.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.10), lineWidth: 1)
                        )

                    PhotosPicker(selection: $editPickerItems, maxSelectionCount: 5, matching: .images) {
                        HStack(spacing: DS.Spacing.sm) {
                            if isLoadingEditImages {
                                ProgressView().tint(DS.Color.primary)
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                            }
                            Text(L10n.t("إضافة صور جديدة", "Add new photos"))
                        }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.md)
                        .background(DS.Color.primary.opacity(0.08))
                        .cornerRadius(DS.Radius.md)
                    }
                    .disabled(isLoadingEditImages)

                    if !existingImageURLs.isEmpty || !selectedImages.isEmpty {
                        let allImages: [(isExisting: Bool, index: Int, urlOrNil: String?)] =
                            existingImageURLs.enumerated().map { (true, $0.offset, $0.element) } +
                            selectedImages.enumerated().map { (false, $0.offset, nil) }

                        TabView {
                            ForEach(Array(allImages.enumerated()), id: \.offset) { _, item in
                                ZStack(alignment: .topTrailing) {
                                    if item.isExisting, let url = item.urlOrNil {
                                        CachedAsyncImage(url: URL(string: url)) { image in
                                            image.resizable().scaledToFill()
                                                .frame(maxWidth: .infinity)
                                                .clipped()
                                        } placeholder: {
                                            ZStack {
                                                DS.Color.surface
                                                ProgressView().tint(DS.Color.primary)
                                            }
                                        }
                                    } else if !item.isExisting, selectedImages.indices.contains(item.index) {
                                        Image(uiImage: selectedImages[item.index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(maxWidth: .infinity)
                                            .clipped()
                                    }

                                    Button {
                                        withAnimation {
                                            if item.isExisting {
                                                existingImageURLs.remove(at: item.index)
                                            } else {
                                                selectedImages.remove(at: item.index)
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(DS.Font.scaled(22, weight: .bold))
                                            .foregroundColor(.white)
                                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                                    }
                                    .padding(DS.Spacing.sm)
                                }
                            }
                        }
                        .aspectRatio(4/5, contentMode: .fit)
                        .clipped()
                        .tabViewStyle(.page(indexDisplayMode: allImages.count > 1 ? .automatic : .never))
                    }

                    if selectedType == "تصويت" {
                        VStack(spacing: DS.Spacing.sm) {
                            TextField(L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $pollQuestion)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الأول", "Option 1"), text: $pollOption1)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الثاني", "Option 2"), text: $pollOption2)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الثالث (اختياري)", "Option 3 (optional)"), text: $pollOption3)
                                .textFieldStyle(.roundedBorder)
                            TextField(L10n.t("الخيار الرابع (اختياري)", "Option 4 (optional)"), text: $pollOption4)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    DSPrimaryButton(
                        L10n.t("حفظ التعديلات", "Save Changes"),
                        icon: "checkmark.circle.fill",
                        isLoading: authVM.isLoading,
                        useGradient: canSubmit,
                        color: canSubmit ? DS.Color.primary : .gray
                    ) {
                        Task { await submitEdits() }
                    }
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1.0 : 0.6)
                }
                .padding(DS.Spacing.lg)
            }
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
            .onChange(of: editPickerItems) { _, items in
                Task {
                    await MainActor.run { isLoadingEditImages = true }
                    var loaded: [UIImage] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) { loaded.append(image) }
                    }
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    await MainActor.run {
                        selectedImages = loaded
                        isLoadingEditImages = false
                    }
                }
            }
            .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
        }
    }

    private func submitEdits() async {
        guard canSubmit else { return }

        var imageURLs = existingImageURLs
        if let authorId = authVM.currentUser?.id {
            for image in selectedImages {
                if let url = await newsVM.uploadNewsImage(image: image, for: authorId) {
                    imageURLs.append(url)
                }
            }
        }

        let question = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUpdated = await newsVM.updateNewsPost(
            postId: news.id,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            type: selectedType,
            imageURLs: imageURLs,
            pollQuestion: selectedType == "تصويت" && !question.isEmpty ? question : nil,
            pollOptions: selectedType == "تصويت" ? normalizedPollOptions : []
        )

        if isUpdated {
            dismiss()
        } else {
            showEditErrorAlert = true
        }
    }
}
