import SwiftUI

struct StoryViewerView: View {
    @EnvironmentObject var storyVM: StoryViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var authVM: AuthViewModel

    @Binding var isPresented: Bool
    let allGroups: [(member: FamilyMember, stories: [FamilyStory])]
    let initialGroupIndex: Int

    @State private var currentGroupIndex: Int = 0
    @State private var currentStoryIndex: Int = 0
    @State private var progress: CGFloat = 0
    @State private var timer: Timer? = nil
    @State private var isPaused: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var showDeleteConfirm = false
    @State private var isApproving = false

    private let storyDuration: TimeInterval = 5.0
    private let screenWidth = UIScreen.main.bounds.width

    var body: some View {
        GeometryReader { geo in
            ZStack {
                DS.Color.overlayDark.opacity(dragOpacity).ignoresSafeArea()

                if !allGroups.isEmpty,
                   currentGroupIndex < allGroups.count,
                   currentStoryIndex < allGroups[currentGroupIndex].stories.count {
                    let group = allGroups[currentGroupIndex]
                    let story = group.stories[currentStoryIndex]

                    // Tap zones — تحت كل شيء
                    tapZones(width: geo.size.width)
                        .zIndex(0)

                    VStack(spacing: 0) {
                        // Progress bars — تحت النوتش بمسافة
                        progressBars(count: group.stories.count)
                            .padding(.horizontal, DS.Spacing.md)
                            .padding(.top, 70)
                            .allowsHitTesting(false)

                        // Header — فوق الـ tap zones (أزرار الحذف والإغلاق)
                        storyHeader(member: group.member, story: story)
                            .padding(.horizontal, DS.Spacing.lg)
                            .padding(.top, DS.Spacing.sm)
                            .zIndex(10)

                        Spacer(minLength: 0)
                            .allowsHitTesting(false)

                        // الصورة — مربعة بنص الشاشة
                        storyImage(story: story)
                            .allowsHitTesting(false)

                        // Caption — تحت الصورة مباشرة
                        if let caption = story.caption, !caption.isEmpty {
                            Text(caption)
                                .font(DS.Font.scaled(16, weight: .semibold))
                                .foregroundColor(DS.Color.textOnPrimary)
                                .dsCardShadow()
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, DS.Spacing.xl)
                                .padding(.top, DS.Spacing.sm)
                                .allowsHitTesting(false)
                        }

                        // عدد المشاهدات — لصاحب القصة فقط
                        if story.createdBy == authVM.currentUser?.id {
                            HStack(spacing: DS.Spacing.xs) {
                                Image(systemName: "eye.fill")
                                    .font(DS.Font.footnote)
                                Text("\(storyVM.viewCounts[story.id] ?? 0)")
                                    .font(DS.Font.scaled(13, weight: .semibold))
                            }
                            .foregroundColor(DS.Color.textOnPrimary.opacity(0.7))
                            .padding(.top, DS.Spacing.sm)
                            .allowsHitTesting(false)
                        }

                        // أزرار الموافقة/الرفض — للمشرف والمدير على القصص المعلقة
                        if canApproveCurrentStory {
                            approveRejectButtons(story: story)
                                .padding(.top, DS.Spacing.md)
                                .zIndex(10)
                        }

                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    }
                    .zIndex(1)
                }
            }
            .offset(y: dragOffset)
            .opacity(dragOpacity)
            .scaleEffect(dragScale)
            .gesture(dismissDragGesture)
        }
        .ignoresSafeArea()
        .statusBarHidden(false)
        .alert(L10n.t("حذف القصة", "Delete Story"), isPresented: $showDeleteConfirm) {
            Button(L10n.t("حذف", "Delete"), role: .destructive) { deleteCurrentStory() }
            Button(L10n.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.t("هل تريد حذف هذه القصة؟", "Do you want to delete this story?"))
        }
        .onAppear {
            currentGroupIndex = min(initialGroupIndex, allGroups.count - 1)
            currentStoryIndex = 0
            startTimer()
            recordAndFetchViews()
        }
        .onDisappear { stopTimer() }
        .onChange(of: currentStoryIndex) { _ in recordAndFetchViews() }
        .onChange(of: currentGroupIndex) { _ in recordAndFetchViews() }
    }

    // MARK: - Story Image (مربعة)

    private func storyImage(story: FamilyStory) -> some View {
        CachedAsyncPhaseImage(url: URL(string: story.imageUrl)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: screenWidth, height: screenWidth)
            } else if phase.error != nil {
                ZStack {
                    DS.Color.overlayDark
                    Image(systemName: "photo.slash")
                        .font(DS.Font.scaled(40, weight: .regular))
                        .foregroundColor(DS.Color.textSecondary)
                }
                .frame(width: screenWidth, height: screenWidth)
            } else {
                ZStack {
                    DS.Color.overlayDark
                    ProgressView().tint(DS.Color.textOnPrimary)
                }
                .frame(width: screenWidth, height: screenWidth)
            }
        }
        .clipped()
    }

    // MARK: - Progress Bars

    private func progressBars(count: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<count, id: \.self) { index in
                GeometryReader { barGeo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DS.Color.overlayIconBorder)
                        Capsule()
                            .fill(DS.Color.textOnPrimary)
                            .frame(width: barWidth(index: index, totalWidth: barGeo.size.width))
                    }
                }
                .frame(height: 2.5)
            }
        }
    }

    private func barWidth(index: Int, totalWidth: CGFloat) -> CGFloat {
        if index < currentStoryIndex {
            return totalWidth
        } else if index == currentStoryIndex {
            return totalWidth * progress
        } else {
            return 0
        }
    }

    // MARK: - Header

    private let headerIconSize: CGFloat = 36

    private func storyHeader(member: FamilyMember, story: FamilyStory) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Group {
                if let avatarUrl = member.avatarUrl, let url = URL(string: avatarUrl) {
                    CachedAsyncPhaseImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            initialCircle(member: member, size: headerIconSize)
                        }
                    }
                } else {
                    initialCircle(member: member, size: headerIconSize)
                }
            }
            .frame(width: headerIconSize, height: headerIconSize)
            .clipShape(Circle())
            .overlay(Circle().stroke(DS.Color.overlayHalf, lineWidth: 1))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: DS.Spacing.sm) {
                    Text(firstAndLastName(member.fullName))
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                    if story.approvalStatus == "pending" {
                        Text(L10n.t("معلقة", "Pending"))
                            .font(DS.Font.scaled(10, weight: .bold))
                            .foregroundColor(DS.Color.warning)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Color.warning.opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                Text(relativeTime(story.createdDate))
                    .font(DS.Font.scaled(11, weight: .medium))
                    .foregroundColor(DS.Color.textOnPrimary.opacity(0.7))
            }

            Spacer()

            // زر حذف — لصاحب القصة أو المدير
            if canDeleteCurrentStory {
                Button { showDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(DS.Font.scaled(14, weight: .bold))
                        .foregroundColor(DS.Color.textOnPrimary)
                        .frame(width: headerIconSize, height: headerIconSize)
                        .background(DS.Color.overlayIcon)
                        .clipShape(Circle())
                }
                .accessibilityLabel(L10n.t("حذف", "Delete"))
            }

            Button { closeViewer() } label: {
                Image(systemName: "xmark")
                    .font(DS.Font.scaled(14, weight: .bold))
                    .foregroundColor(DS.Color.textOnPrimary)
                    .frame(width: headerIconSize, height: headerIconSize)
                    .background(DS.Color.overlayIcon)
                    .clipShape(Circle())
            }
            .accessibilityLabel(L10n.t("إغلاق", "Close"))
        }
    }

    /// الاسم الأول والأخير فقط
    private func firstAndLastName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ")
        if parts.count <= 2 { return fullName }
        return "\(parts.first ?? "") \(parts.last ?? "")"
    }

    // MARK: - Tap Zones

    private func tapZones(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { previousStory() }
                .frame(width: width * 0.3)

            Color.clear
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
                    isPaused = pressing
                }, perform: {})
                .frame(width: width * 0.4)

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { nextStory() }
                .frame(width: width * 0.3)
        }
    }

    // MARK: - Drag to Dismiss

    /// شفافية تدريجية — من 1 إلى 0 كل ما نزل أكثر
    private var dragOpacity: Double {
        let maxDrag: CGFloat = 300
        return Double(max(1 - dragOffset / maxDrag, 0.3))
    }

    /// تصغير تدريجي خفيف
    private var dragScale: CGFloat {
        let maxDrag: CGFloat = 300
        return max(1 - dragOffset / maxDrag * 0.15, 0.85)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 100 {
                    closeViewer()
                } else {
                    withAnimation(DS.Anim.snappy) { dragOffset = 0 }
                }
            }
    }

    // MARK: - Delete

    private var canDeleteCurrentStory: Bool {
        guard !allGroups.isEmpty,
              currentGroupIndex < allGroups.count,
              currentStoryIndex < allGroups[currentGroupIndex].stories.count else { return false }
        let story = allGroups[currentGroupIndex].stories[currentStoryIndex]
        let isCreator = story.createdBy == authVM.currentUser?.id
        let role = authVM.currentUser?.role
        // فقط المدير أو المالك أو صاحب القصة
        return isCreator || authVM.canDeleteStories
    }

    /// هل القصة الحالية معلقة ويقدر المستخدم يوافق/يرفض؟
    private var canApproveCurrentStory: Bool {
        guard authVM.canModerate,
              !allGroups.isEmpty,
              currentGroupIndex < allGroups.count,
              currentStoryIndex < allGroups[currentGroupIndex].stories.count else { return false }
        let story = allGroups[currentGroupIndex].stories[currentStoryIndex]
        return story.approvalStatus == "pending"
    }

    private func deleteCurrentStory() {
        guard !allGroups.isEmpty,
              currentGroupIndex < allGroups.count,
              currentStoryIndex < allGroups[currentGroupIndex].stories.count else { return }
        let story = allGroups[currentGroupIndex].stories[currentStoryIndex]
        Task {
            await storyVM.deleteStory(story)
            // لو ما بقى ستوريات — اقفل العارض
            if storyVM.membersWithStories.isEmpty {
                closeViewer()
            } else {
                // انتقل للتالي أو اقفل
                nextStory()
            }
        }
    }

    // MARK: - Approve / Reject

    private func approveRejectButtons(story: FamilyStory) -> some View {
        HStack(spacing: DS.Spacing.md) {
            // رفض
            Button {
                guard !isApproving else { return }
                isApproving = true
                Task {
                    await storyVM.rejectStory(story)
                    isApproving = false
                    if storyVM.membersWithStories.isEmpty {
                        closeViewer()
                    } else {
                        nextStory()
                    }
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Font.scaled(16, weight: .bold))
                    Text(L10n.t("رفض", "Reject"))
                        .font(DS.Font.scaled(14, weight: .bold))
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.error.opacity(0.8))
                .clipShape(Capsule())
            }

            // موافقة
            Button {
                guard !isApproving else { return }
                isApproving = true
                Task {
                    await storyVM.approveStory(story)
                    isApproving = false
                }
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    if isApproving {
                        ProgressView()
                            .tint(DS.Color.textOnPrimary)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(DS.Font.scaled(16, weight: .bold))
                    }
                    Text(L10n.t("موافقة", "Approve"))
                        .font(DS.Font.scaled(14, weight: .bold))
                }
                .foregroundColor(DS.Color.textOnPrimary)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.sm)
                .background(DS.Color.success.opacity(0.8))
                .clipShape(Capsule())
            }
        }
        .disabled(isApproving)
    }

    // MARK: - Views Tracking

    private func recordAndFetchViews() {
        guard currentGroupIndex < allGroups.count,
              currentStoryIndex < allGroups[currentGroupIndex].stories.count else { return }
        let story = allGroups[currentGroupIndex].stories[currentStoryIndex]

        Task {
            // تسجيل المشاهدة
            await storyVM.recordView(storyId: story.id)

            // جلب عدد المشاهدات إذا صاحب القصة
            if story.createdBy == authVM.currentUser?.id {
                await storyVM.fetchViewCounts(storyIds: [story.id])
            }
        }
    }

    // MARK: - Close

    private func closeViewer() {
        withAnimation(.easeOut(duration: 0.3)) {
            isPresented = false
        }
    }

    // MARK: - Helpers

    private func initialCircle(member: FamilyMember, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(DS.Color.primary.opacity(0.4))
            Text(String(member.firstName.prefix(1)))
                .font(DS.Font.scaled(size * 0.4, weight: .bold))
                .foregroundColor(DS.Color.textOnPrimary)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        progress = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                guard !isPaused else { return }
                progress += 0.05 / storyDuration
                if progress >= 1 { nextStory() }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Navigation

    private func nextStory() {
        guard currentGroupIndex < allGroups.count else { closeViewer(); return }
        let group = allGroups[currentGroupIndex]
        if currentStoryIndex < group.stories.count - 1 {
            currentStoryIndex += 1
            progress = 0
        } else if currentGroupIndex < allGroups.count - 1 {
            currentGroupIndex += 1
            currentStoryIndex = 0
            progress = 0
        } else {
            closeViewer()
            return
        }
        startTimer()
    }

    private func previousStory() {
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
            progress = 0
        } else if currentGroupIndex > 0 {
            currentGroupIndex -= 1
            let prevGroup = allGroups[currentGroupIndex]
            currentStoryIndex = prevGroup.stories.count - 1
            progress = 0
        } else {
            progress = 0
        }
        startTimer()
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func relativeTime(_ date: Date) -> String {
        Self.relativeDateFormatter.locale = L10n.isArabic ? Locale(identifier: "ar") : Locale(identifier: "en_US")
        return Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
