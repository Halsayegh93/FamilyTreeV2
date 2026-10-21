import SwiftUI
import PhotosUI
import Photos

// MARK: - تعديل خبر — نفس مربّع «خبر جديد» (طلب المالك ٢٠٢٦-٠٩-٢٦)
//
// رأس بلون نوع الخبر، «التصنيف»، ثم «محتوى الخبر» مع صوره (الحالية والجديدة)،
// والتصويت في مربّع إضافي مثل الإضافة. «حفظ» كحلي يمين و«إلغاء» يسار.
// منطق التعديل والحفظ كما هو بلا تغيير.
struct EditNewsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @Environment(\.dismiss) var dismiss
    /// «تقليل الحركة» (توصية أبل): تلاشٍ بدل التكبير والانزلاق
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

        _initialDraft = State(initialValue: Draft(
            content: news.content.trimmingCharacters(in: .whitespacesAndNewlines),
            type: news.type,
            imageURLs: news.mediaURLs,
            hasNewImages: false,
            pollQuestion: (news.poll_question ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pollOptions: options.prefix(4)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        ))
    }

    // MARK: - تغييرات لم تُحفظ (توصية أبل)

    /// ما يُحفظ من المربّع — يُقارَن بما فُتح به، فـ«إلغاء» يسأل قبل تجاهل أي تعديل
    private struct Draft: Equatable {
        var content: String
        var type: String
        var imageURLs: [String]
        var hasNewImages: Bool
        var pollQuestion: String
        var pollOptions: [String]
    }

    /// القيم التي فُتح بها المربّع — تُلتقط مرة واحدة
    @State private var initialDraft: Draft

    private var hasUnsavedChanges: Bool {
        Draft(content: content.trimmingCharacters(in: .whitespacesAndNewlines),
              type: selectedType,
              imageURLs: existingImageURLs,
              hasNewImages: !selectedImages.isEmpty || isLoadingPhotos,
              pollQuestion: pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines),
              pollOptions: normalizedPollOptions) != initialDraft
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
        guard selectedImages.isEmpty || totalPhotos <= Self.photoLimit else { return false }
        if isPoll {
            return isPollValid && !isSubmitting
        } else {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
        }
    }

    // MARK: - الصور (الحالية + الجديدة بحد ٥ كما كان)

    private static var photoLimit: Int { RemoteSettings.int("news_max_photos", 5, range: 1...10) }
    /// مصغّرات الصور بمقاس شريط صور «خبر جديد» (`DSComposerPhotoStrip`)
    private static let thumbSize: CGFloat = DSBox.photoTile

    private var totalPhotos: Int { existingImageURLs.count + selectedImages.count }

    // MARK: - المربّع الإضافي (التصويت)

    private enum NewsExtra: String, Identifiable { case poll; var id: String { rawValue } }
    @State private var activeExtra: NewsExtra?
    @State private var draftQuestion = ""
    @State private var draftOptions: [PollDraft] = [PollDraft(), PollDraft()]
    @FocusState private var contentFocused: Bool

    private struct PollDraft: Identifiable, Equatable {
        let id = UUID()
        var text = ""
    }

    /// التصنيفات كما كانت في التعديل (كل الأنواع الظاهرة) عدا «تصويت» —
    /// التصويت من زره جنب الصور مثل «خبر جديد»
    private var availableTypes: [String] {
        NewsTypeHelper.mainTypes.filter { $0 != "تصويت" }
    }

    /// التحويل لتصويت متاح كما في محدّد الأنواع السابق: متى كان «تصويت» ظاهراً
    /// (أو الخبر تصويت أصلاً)
    private var pollAvailable: Bool {
        isPoll || NewsTypeHelper.mainTypes.contains("تصويت")
    }

    /// لون الرأس — يتبع نوع الخبر؛ الإعلان والخبر بالكحلي الغامق (لونهما primary
    /// يفتح في الداكن فيضعف النص الأبيض)
    private var headerTint: Color {
        if isPoll { return DS.Color.newsVote }
        if isPlainNewsType { return AppSection.news.fill }
        if selectedType == "إعلان" || selectedType == "خبر" { return DS.Color.brandFill }   // كحلي ثابت (معنى)
        return NewsTypeHelper.color(for: selectedType)
    }

    /// لون الأقسام والأيقونات داخل المربّع — ألوان الأنواع التكيّفية (تُقرأ في الوضعين)
    private var sectionTint: Color {
        if isPoll { return DS.Color.newsVote }
        if isPlainNewsType { return AppSection.news.ink }
        return NewsTypeHelper.color(for: selectedType)
    }

    /// «خبر» العادي (أو نوع بلا لون خاص) — إطار المربّع بلون قسم الأخبار لا بكحلي العلامة
    /// (طلب المالك ٢٠٢٦-١٠-٠٥ «وحتى الاخبار»). الأنواع ذات المعنى (إعلان، زواج، وفاة…) بلونها.
    private var isPlainNewsType: Bool {
        selectedType != "إعلان" && NewsTypeHelper.color(for: selectedType) == DS.Color.brand
    }

    private var headerIcon: String {
        isPoll ? "chart.bar.fill" : NewsTypeHelper.icon(for: selectedType)
    }

    var body: some View {
        DSComposer(
            title: L10n.t("تعديل الخبر", "Edit Post"),
            subtitle: isPoll ? L10n.t("تصويت لأفراد العائلة", "A poll for the family")
                             : L10n.t("تحديث الخبر · \(NewsTypeHelper.displayName(for: selectedType))",
                                      "Update the post · \(NewsTypeHelper.displayName(for: selectedType))"),
            icon: headerIcon,
            tint: headerTint,
            actionTitle: L10n.t("حفظ", "Save"),
            canSubmit: canSubmit,
            isBusy: isSubmitting,
            isBehindExtra: activeExtra != nil,
            hasUnsavedChanges: hasUnsavedChanges,
            onSubmit: { Task { await submitEdits() } },
            onCancel: { dismiss() }
        ) {
            categorySection
            contentSection
        }
        .dsExtraBox(item: $activeExtra) { _ in pollBox }
        .dsAlert(L10n.t("تعذر التعديل", "Edit Failed"), isPresented: $showEditErrorAlert) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: { Text(newsVM.newsPostErrorMessage ?? L10n.t("حدث خطأ أثناء تعديل الخبر.", "An error occurred while updating.")) }
        .onChange(of: pickerItems) { items in
            guard !items.isEmpty else { return }
            loadImages(from: items)
        }
        // مربّع الأخبار بلون قسم الأخبار (زر الحفظ، التصويت، الرسائل)
        .dsSectionPage(.news)
    }

    // MARK: - التصنيف

    private var categorySection: some View {
        DSComposerSection(
            title: L10n.t("نوع الخبر", "Post Type"),
            icon: "square.grid.2x2.fill",
            tint: sectionTint,
            trailing: isPoll ? L10n.t("غير مطلوب للتصويت", "Not needed for polls") : nil,
            index: 0
        ) {
            // مربّعات الاختيار الموحّدة (`DSOptionTiles`، صفوف عادية لا تُقصّ) — مشتركة مع «خبر جديد»
            NewsTypeTiles(types: availableTypes, selection: $selectedType, disabled: isPoll)
        }
    }

    // MARK: - المحتوى (مع الصور والتصويت)

    private var contentSection: some View {
        DSComposerSection(
            title: isPoll ? L10n.t("خيارات التصويت", "Poll Options") : L10n.t("محتوى الخبر", "Post Content"),
            icon: isPoll ? "chart.bar.fill" : "text.alignright",
            tint: sectionTint,
            trailing: (!isPoll && !content.isEmpty) ? "\(content.count)" : nil,
            index: 1
        ) {
            if isPoll {
                pollPreview
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
            } else {
                contentEditor

                // الصور الحالية والجديدة
                if totalPhotos > 0 {
                    photoStrip
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }

            // أدوات المحتوى: الصور والتصويت داخل محتوى الخبر (مثل «خبر جديد»)
            if (!isPoll && totalPhotos == 0) || pollAvailable {
                contentTools
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isPoll)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: totalPhotos)
    }

    private var contentEditor: some View {
        NewsContentEditor(text: $content, placeholder: L10n.t("اكتب الخبر هنا...", "Write your post here..."),
                          tint: sectionTint, focused: $contentFocused)
    }

    private var contentTools: some View {
        HStack(spacing: DS.Spacing.sm) {
            if !isPoll && totalPhotos == 0 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, Self.photoLimit - existingImageURLs.count),
                    matching: .images
                ) {
                    // نفس وجه شريحة «تصويت» جنبها (DSExtraChip)
                    DSAddChipLabel(icon: "photo.on.rectangle.angled", title: L10n.t("صور", "Photos"),
                                   isLoading: isLoadingPhotos)
                }
                .disabled(isLoadingPhotos || totalPhotos >= Self.photoLimit)
                .accessibilityLabel(L10n.t("إضافة صور", "Add photos"))
            }
            if pollAvailable {
                DSExtraChip(
                    icon: "chart.bar.fill",
                    title: L10n.t("تصويت", "Poll"),
                    tint: DS.Color.newsVote,
                    summary: isPoll ? L10n.t("تصويت · \(normalizedPollOptions.count) خيارات",
                                             "Poll · \(normalizedPollOptions.count) options") : nil
                ) { openPollBox() }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - شريط الصور (الحالية من الرابط + الجديدة)

    private var photoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                addPhotoTile

                // الصور الموجودة (URLs)
                ForEach(Array(existingImageURLs.enumerated()), id: \.offset) { idx, url in
                    CachedAsyncImage(url: URL(string: url)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ZStack {
                            DS.Color.surface
                            ProgressView().tint(sectionTint).scaleEffect(0.7)   // دوّارة صغيرة داخل المصغّرة
                        }
                    }
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous))
                    .overlay(alignment: .topLeading) {
                        removePhotoButton {
                            _ = withAnimation(DS.Anim.snappy) {
                                existingImageURLs.remove(at: idx)
                            }
                        }
                    }
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }

                // الصور الجديدة (UIImage)
                ForEach(Array(selectedImages.enumerated()), id: \.offset) { idx, image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: Self.thumbSize, height: Self.thumbSize)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            removePhotoButton {
                                _ = withAnimation(DS.Anim.snappy) {
                                    selectedImages.remove(at: idx)
                                }
                            }
                        }
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.vertical, DS.Spacing.xxs)
        }
    }

    /// مربّع «إضافة» أول الشريط — بعدّاد الصور (الحد ٥ مع الحالية كما كان)
    private var addPhotoTile: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: max(1, Self.photoLimit - existingImageURLs.count),
            matching: .images
        ) {
            VStack(spacing: DS.Spacing.xxs) {
                if isLoadingPhotos {
                    ProgressView().tint(sectionTint)   // دوّارة صغيرة داخل الخانة
                } else {
                    Image(systemName: "photo.badge.plus")
                        .dsGlyph(DS.Glyph.lg, weight: .semibold)
                    Text(L10n.t("إضافة", "Add")).dsFont(.badge)
                    Text("\(totalPhotos)/\(Self.photoLimit)")
                        .dsFont(.micro)
                        .monospacedDigit()
                }
            }
            .foregroundColor(sectionTint)
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .background(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                .fill(sectionTint.opacity(DS.Opacity.tintFillSoft)))
            .overlay(RoundedRectangle(cornerRadius: DS.Icon.discRadius, style: .continuous)
                .strokeBorder(sectionTint.opacity(DSAddChipLabel.strokeOpacity), style: DSAddChipLabel.dash))
        }
        .disabled(isLoadingPhotos || totalPhotos >= Self.photoLimit)
        .opacity(totalPhotos >= Self.photoLimit ? DS.Opacity.disabled : 1)
        .accessibilityLabel(L10n.t("إضافة صور", "Add photos"))
    }

    /// زر حذف الصورة داخل الصورة المصغّرة — نفس شريط صور «خبر جديد»
    private func removePhotoButton(_ remove: @escaping () -> Void) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            remove()
        } label: {
            Image(systemName: "xmark")
                .dsGlyph(DS.Glyph.micro, weight: .heavy)
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: DS.Icon.section, height: DS.Icon.section)
                .background(Circle().fill(DS.Color.shadowOverlay))
                .padding(DS.Spacing.xs)
                // مساحة ضغط ٤٤×٤٤ من زاوية الصورة (الصورة هنا لا تُضغط) — الشارة كما هي
                .frame(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("حذف الصورة", "Remove photo"))
    }

    // MARK: - معاينة التصويت داخل المحتوى — الضغط يفتحه للتعديل

    private var pollPreview: some View {
        NewsPollPreview(question: pollQuestion, options: normalizedPollOptions,
                        onEdit: { openPollBox() },
                        onRemove: { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { removePoll() } })
    }

    // MARK: - مربّع التصويت (سؤال اختياري + خياران إلى أربعة — كما كان)

    private var draftValidCount: Int {
        draftOptions.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private var pollBox: some View {
        DSExtraBox(
            title: L10n.t("تصويت", "Poll"),
            subtitle: L10n.t("خياران على الأقل، وحتى أربعة", "At least two options, up to four"),
            icon: "chart.bar.fill",
            tint: DS.Color.newsVote,
            doneTitle: isPoll ? L10n.t("حفظ", "Save") : L10n.t("إضافة التصويت", "Add poll"),
            doneEnabled: draftValidCount >= 2,
            onDone: commitPoll,
            onCancel: { dsCloseExtra { activeExtra = nil } }
        ) {
            VStack(spacing: DS.Spacing.sm) {
                TextField(L10n.t("سؤال التصويت (اختياري)", "Poll question (optional)"), text: $draftQuestion)
                    .dsAlertField()
                ForEach(Array(draftOptions.enumerated()), id: \.element.id) { idx, option in
                    pollDraftRow(idx: idx, option: option)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
                if draftOptions.count < 4 {
                    NewsPollAddOptionButton {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            draftOptions.append(PollDraft())
                        }
                    }
                }
            }
        }
    }

    private func pollDraftRow(idx: Int, option: PollDraft) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            NewsPollNumber(number: idx + 1, size: DS.Spacing.xxl)
            TextField(idx < 2 ? L10n.t("الخيار \(idx + 1)", "Option \(idx + 1)")
                              : L10n.t("الخيار \(idx + 1) (اختياري)", "Option \(idx + 1) (optional)"),
                      text: Binding(
                        get: { draftOptions.first(where: { $0.id == option.id })?.text ?? "" },
                        set: { v in
                            if let i = draftOptions.firstIndex(where: { $0.id == option.id }) {
                                draftOptions[i].text = v
                            }
                        }))
                .dsAlertField()
            if draftOptions.count > 2 {
                NewsPollRemoveOptionButton(label: L10n.t("حذف الخيار \(idx + 1)", "Remove option \(idx + 1)")) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        draftOptions.removeAll { $0.id == option.id }
                    }
                }
            }
        }
    }

    private func openPollBox() {
        draftQuestion = pollQuestion
        let existing = [pollOption1, pollOption2, pollOption3, pollOption4]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var drafts = existing.map { PollDraft(text: $0) }
        while drafts.count < 2 { drafts.append(PollDraft()) }
        draftOptions = drafts
        contentFocused = false
        activeExtra = .poll
    }

    private func commitPoll() {
        let opts = draftOptions.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        pollQuestion = draftQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        pollOption1 = opts.count > 0 ? opts[0] : ""
        pollOption2 = opts.count > 1 ? opts[1] : ""
        pollOption3 = opts.count > 2 ? opts[2] : ""
        pollOption4 = opts.count > 3 ? opts[3] : ""
        dsCloseExtra { activeExtra = nil }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { selectedType = "تصويت" }
    }

    /// إزالة التصويت = الرجوع لخبر عادي (مثل اختيار نوع آخر سابقاً) — يُختار «إعلان»
    /// إن وُجد ويمكن تغييره من «نوع الخبر»
    private func removePoll() {
        pollQuestion = ""; pollOption1 = ""; pollOption2 = ""; pollOption3 = ""; pollOption4 = ""
        let types = availableTypes
        selectedType = types.contains("إعلان") ? "إعلان" : (types.first ?? "إعلان")
    }

    // MARK: - Load Images
    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            isLoadingPhotos = true
            var loaded: [UIImage] = []
            for item in items {
                // فكّ مصغّر خارج الخيط الرئيسي (كان يعلّق عند إضافة الصور — ٢٠٢٦-١٠-٠٥)
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = await Task.detached(priority: .userInitiated, operation: {
                       ImageProcessor.downsampled(data)
                   }).value {
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
        // تحقق من الصلاحية — صاحب الخبر أو المدير
        guard authVM.currentUser?.id == news.ownerId || authVM.canDeleteNews else { return }
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
