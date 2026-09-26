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
        if isPoll {
            return isPollValid && !isSubmitting
        } else {
            return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubmitting
        }
    }

    // MARK: - الصور (الحالية + الجديدة بحد ٥ كما كان)

    private static let photoLimit = 5
    private static let thumbSize: CGFloat = 68

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
        if selectedType == "إعلان" || selectedType == "خبر" { return DS.Color.actionNavy }
        return NewsTypeHelper.color(for: selectedType)
    }

    /// لون الأقسام والأيقونات داخل المربّع — ألوان الأنواع التكيّفية (تُقرأ في الوضعين)
    private var sectionTint: Color {
        isPoll ? DS.Color.newsVote : NewsTypeHelper.color(for: selectedType)
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
            // صفوف عادية لا LazyVGrid — الشبكة الكسولة تُبلِّغ ارتفاعاً ناقصاً فيُقصّ آخر صف
            let types = availableTypes
            VStack(spacing: DS.Spacing.sm) {
                ForEach(Array(stride(from: 0, to: types.count, by: 4)), id: \.self) { start in
                    let end = min(start + 4, types.count)
                    HStack(spacing: DS.Spacing.sm) {
                        ForEach(types[start..<end], id: \.self) { type in
                            categoryTile(type)
                        }
                        ForEach(0..<(4 - (end - start)), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                    }
                }
            }
            .opacity(isPoll ? 0.4 : 1)
            .allowsHitTesting(!isPoll)
        }
    }

    private func categoryTile(_ type: String) -> some View {
        let selected = !isPoll && selectedType == type
        // الإعلان/الخبر: primary (كحلي في الفاتح، أزرق فاتح يُقرأ في الداكن)
        let c = NewsTypeHelper.color(for: type)
        return Button {
            guard selectedType != type else { return }
            withAnimation(DS.Anim.snappy) { selectedType = type }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: NewsTypeHelper.icon(for: type))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(selected ? .white : c)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(selected ? AnyShapeStyle(LinearGradient(colors: [c, c.opacity(0.75)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(c.opacity(0.13))))
                    .shadow(color: selected ? c.opacity(0.45) : .clear, radius: 8, y: 3)
                    // «تقليل الحركة»: بلا تكبير — اللون وحده يدلّ على الاختيار
                    .scaleEffect(selected && !reduceMotion ? 1.08 : 1)
                    .accessibilityHidden(true)
                Text(NewsTypeHelper.displayName(for: type))
                    .font(DS.Font.plex(11.5, weight: selected ? .bold : .semibold))
                    .foregroundColor(selected ? c : DS.Color.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.sm + 1)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(selected ? c.opacity(0.10) : DS.Color.background))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(selected ? c.opacity(0.55) : DS.Color.textTertiary.opacity(0.12),
                              lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(DSScaleButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
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
        ZStack(alignment: .topLeading) {
            TextEditor(text: $content)
                .focused($contentFocused)
                .frame(minHeight: 104, maxHeight: 190)
                .scrollContentBackground(.hidden)
                .font(DS.Font.plex(15))
                .foregroundColor(DS.Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            if content.isEmpty {
                Text(L10n.t("اكتب الخبر هنا...", "Write your post here..."))
                    .font(DS.Font.plex(15))
                    .foregroundColor(DS.Color.textTertiary)
                    .padding(.horizontal, 11)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.background))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(contentFocused ? sectionTint.opacity(0.6) : DS.Color.textTertiary.opacity(0.15),
                          lineWidth: contentFocused ? 1.5 : 1))
        .animation(.easeInOut(duration: 0.2), value: contentFocused)
    }

    private var contentTools: some View {
        HStack(spacing: DS.Spacing.sm) {
            if !isPoll && totalPhotos == 0 {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(1, Self.photoLimit - existingImageURLs.count),
                    matching: .images
                ) {
                    HStack(spacing: 6) {
                        if isLoadingPhotos {
                            ProgressView().scaleEffect(0.7).tint(sectionTint)
                        } else {
                            Image(systemName: "plus").font(.system(size: 11.5, weight: .bold))
                            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 11.5, weight: .semibold))
                        }
                        Text(L10n.t("صور", "Photos")).font(DS.Font.plex(12, weight: .bold))
                    }
                    .foregroundColor(DS.Color.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .overlay(Capsule().strokeBorder(DS.Color.textTertiary.opacity(0.4),
                                                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 3])))
                    // مساحة ضغط ٤٤ نقطة مثل شارة «تصويت» جنبها (DSExtraChip) — الشكل كما هو
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
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
                            ProgressView().tint(sectionTint).scaleEffect(0.7)
                        }
                    }
                    .frame(width: Self.thumbSize, height: Self.thumbSize)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
            .padding(.vertical, 2)
        }
    }

    /// مربّع «إضافة» أول الشريط — بعدّاد الصور (الحد ٥ مع الحالية كما كان)
    private var addPhotoTile: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: max(1, Self.photoLimit - existingImageURLs.count),
            matching: .images
        ) {
            VStack(spacing: 3) {
                if isLoadingPhotos {
                    ProgressView().tint(sectionTint)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                    Text(L10n.t("إضافة", "Add")).font(DS.Font.plex(11, weight: .bold))
                    Text("\(totalPhotos)/\(Self.photoLimit)")
                        .font(DS.Font.plex(10, weight: .semibold))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundColor(sectionTint)
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(sectionTint.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .strokeBorder(sectionTint.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
        }
        .disabled(isLoadingPhotos || totalPhotos >= Self.photoLimit)
        .opacity(totalPhotos >= Self.photoLimit ? 0.45 : 1)
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
                .font(.system(size: 9.5, weight: .heavy))
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DS.Color.overlayDark.opacity(0.55)))
                .padding(5)
                // مساحة ضغط ٤٤×٤٤ من زاوية الصورة (الصورة هنا لا تُضغط) — الشارة كما هي
                .frame(width: 44, height: 44, alignment: .topLeading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.t("حذف الصورة", "Remove photo"))
    }

    // MARK: - معاينة التصويت داخل المحتوى — الضغط يفتحه للتعديل

    private var pollPreview: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            let q = pollQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
            Text(q.isEmpty ? L10n.t("تصويت بدون سؤال", "Poll without a question") : q)
                .font(DS.Font.plex(14, weight: .bold))
                .foregroundColor(q.isEmpty ? DS.Color.textTertiary : DS.Color.textPrimary)
            ForEach(Array(normalizedPollOptions.enumerated()), id: \.offset) { idx, option in
                HStack(spacing: DS.Spacing.sm) {
                    Text("\(idx + 1)")
                        .font(DS.Font.plex(11, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(DS.Color.newsVote))
                    Text(option)
                        .font(DS.Font.plex(13))
                        .foregroundColor(DS.Color.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.sm)
                .frame(height: 34)
                .background(
                    GeometryReader { g in
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(DS.Color.newsVote.opacity(0.10))
                            .frame(width: g.size.width * CGFloat(0.35 + 0.15 * Double((idx * 7) % 4)))
                    }
                )
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DS.Color.background))
            }
            HStack {
                // النص ١٨ نقطة ← مساحة ضغط ٤٤ (١٣ فوق وتحت) بلا تغيير في التخطيط:
                // فوقه صف خيار غير قابل للضغط، وتحته ٢٠ نقطة قبل شارة «تصويت»
                Button { openPollBox() } label: {
                    Label(L10n.t("تعديل", "Edit"), systemImage: "pencil")
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.newsVote)
                        .tapArea(vertical: 13)
                }
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { removePoll() }
                } label: {
                    Label(L10n.t("إزالة التصويت", "Remove poll"), systemImage: "trash")
                        .font(DS.Font.plex(12, weight: .bold))
                        .foregroundColor(DS.Color.error)
                        .tapArea(vertical: 13)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(DS.Spacing.sm + 2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).fill(DS.Color.newsVote.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
            .strokeBorder(DS.Color.newsVote.opacity(0.3), lineWidth: 1))
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
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            draftOptions.append(PollDraft())
                        }
                    } label: {
                        Label(L10n.t("خيار آخر", "Another option"), systemImage: "plus")
                            .font(DS.Font.plex(12.5, weight: .bold))
                            .foregroundColor(DS.Color.newsVote)
                            .frame(maxWidth: .infinity).frame(height: 38)
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .strokeBorder(DS.Color.newsVote.opacity(0.45),
                                              style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])))
                            // ٣٨ ← مساحة ضغط ٤٤ (٣ فوق وتحت، ضمن المسافة للجيران) بلا تغيير في التخطيط
                            .tapArea(vertical: 3)
                    }
                    .buttonStyle(DSScaleButtonStyle())
                }
            }
        }
    }

    private func pollDraftRow(idx: Int, option: PollDraft) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            Text("\(idx + 1)")
                .font(DS.Font.plex(12, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(DS.Color.newsVote))
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
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                        draftOptions.removeAll { $0.id == option.id }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(DS.Color.error.opacity(0.85))
                        // الدائرة ٢٤ ← مساحة ضغط ٤٤×٤٤: نحو الحقل بقدر المسافة فقط (بلا
                        // تغطيته)، والباقي في هامش المربّع؛ والصفوف متباعدة ٤٦ فلا تتداخل
                        .tapArea(top: 10, leading: 8, bottom: 10, trailing: 12)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("حذف الخيار \(idx + 1)", "Remove option \(idx + 1)"))
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

// MARK: - مساحة ضغط أكبر (توصية أبل: ٤٤ نقطة)

private extension View {
    /// يكبّر منطقة اللمس حول عنصر صغير بلا تغيير في شكله ولا في التخطيط: الحشوة تُضاف
    /// لمنطقة اللمس ثم تُسترد من التخطيط. القيم محسوبة لكل عنصر حتى لا تتداخل مع جيرانه.
    func tapArea(top: CGFloat = 0, leading: CGFloat = 0, bottom: CGFloat = 0, trailing: CGFloat = 0) -> some View {
        self
            .padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .contentShape(Rectangle())
            .padding(EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing))
    }

    func tapArea(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        tapArea(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
    }
}
