import SwiftUI
import PhotosUI

// MARK: - السؤال الرابع في «إعلان»: «يظهر عند فتح التطبيق؟» (العينة launch-announcements، الشاشة ١)
//
// مفتاح (مطفأ افتراضياً)، ومعه: الصورة (مطلوبة، مصغّرة ٤:٥ كما ستظهر، وسطر المقاس المناسب) · «لين:» يوم · يومين ·
// اختر تاريخ ⌄ (ينتهي ٢٣:٥٩ بتوقيت الكويت) · «الزر:» حدّث الحين ← المتجر · افتح الأخبار · رابط ⌄ · بدون زر.
// «لمن؟» و«متى؟» من أسئلة المنشئ نفسها. الحفظ في `AdminAnnounceComposer.send()` ← `LaunchAnnouncementsService`.

/// مدّة الظهور
enum AdminLaunchDuration: Hashable {
    case day, twoDays, until
}

/// الخيارات المختارة — تُحسب منها النهاية ونصّ الزرّ وما يمنع الإرسال
struct AdminLaunchChoice {
    var duration: AdminLaunchDuration
    /// اليوم المختار لـ«اختر تاريخ»
    var untilDay: Date
    var button: LaunchAnnouncement.Kind
    var link: String

    /// يوم/يومين = البداية + ٢٤/٤٨ ساعة؛ التاريخ = ٢٣:٥٩ بتوقيت الكويت ذلك اليوم
    func endsAt(start: Date) -> Date {
        switch duration {
        case .day:     return start.addingTimeInterval(24 * 3600)
        case .twoDays: return start.addingTimeInterval(48 * 3600)
        case .until:   return Self.kuwaitEndOfDay(untilDay)
        }
    }

    static func kuwaitEndOfDay(_ day: Date) -> Date {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var kuwait = Calendar(identifier: .gregorian)
        kuwait.timeZone = AppUpdateDates.kuwait
        var end = DateComponents()
        end.year = parts.year; end.month = parts.month; end.day = parts.day
        end.hour = 23; end.minute = 59
        return kuwait.date(from: end) ?? day
    }

    /// «انشر الإعلان · يظهر عند الفتح يومين» — زرّ الوضع الخاص (إعلان عند الفتح وحده)
    var publishTitle: String {
        L10n.t("انشر الإعلان · يظهر عند الفتح ", "Publish · shows on open ") + durationWords
    }

    /// « · ويظهر عند الفتح يومين» — يُضاف لنصّ زرّ الإرسال
    var sendSuffix: String {
        " · " + L10n.t("ويظهر عند الفتح ", "and shows on open ") + durationWords
    }

    /// «يوم» · «يومين» · «لين 14 نوفمبر»
    var durationWords: String {
        switch duration {
        case .day:     return L10n.t("يوم", "1 day")
        case .twoDays: return L10n.t("يومين", "2 days")
        case .until:   return L10n.t("حتى \(AdminOccasionsText.shortDate(untilDay))",
                                     "until \(AdminOccasionsText.shortDate(untilDay))")
        }
    }

    /// ما يمنع الحفظ — nil = جاهز
    func blocker(hasImage: Bool, start: Date) -> String? {
        if !hasImage { return L10n.t("اختر صورة الإعلان", "Pick the announcement image") }
        if button == .link && LaunchAnnouncementOverlay.linkURL(link) == nil {
            return L10n.t("اكتب الرابط", "Write the link")
        }
        if endsAt(start: start) <= start {
            return L10n.t("اختر تاريخاً بعد وقت الإرسال", "Pick a date after the send time")
        }
        return nil
    }
}

struct AdminLaunchComposerSection: View {
    @Binding var isOn: Bool
    @Binding var image: UIImage?
    @Binding var choice: AdminLaunchChoice
    var tint: Color
    var index: Int = 1
    /// «＋ إعلان جديد» في بطاقة «الإعلانات عند الفتح» (المالك ٢٠٢٦-١١-١٢): بلا المفتاح (مفعّل ضمناً)، و«لمن؟» من المنشئ
    /// تحت الصورة — الترتيب: الصورة · لمن؟ · لين: · الزر:
    var launchOnly: Bool = false
    /// «لمن؟» — شرائح المنشئ نفسها (`AdminAnnounceComposer.audienceBlock`)، في الوضع الخاص فقط
    var audience: AnyView? = nil

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var loadingImage = false
    @State private var dateOpen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DSComposerSection(title: launchOnly ? L10n.t("الإعلان", "Announcement")
                                            : L10n.t("يظهر عند فتح التطبيق؟", "Show when the app opens?"),
                          icon: "rectangle.portrait.on.rectangle.portrait.fill", tint: tint, index: index) {
            if !launchOnly { toggleRow }
            if isOn || launchOnly {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    imageBlock
                    if let audience {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            label(L10n.t("لمن؟", "To whom?"))
                            audience
                        }
                    }
                    durationBlock
                    buttonBlock
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : DS.Anim.snappy, value: isOn)
        .onChange(of: pickerItem) { item in
            guard let item else { return }
            loadImage(item)
        }
    }

    private var toggleRow: some View {
        HStack(spacing: DS.Spacing.sm) {
            Text(L10n.t("يظهر كل ما يفتحون التطبيق", "Shows every time members open the app"))
                .dsFieldFont(.rowTitle)
                .foregroundColor(DS.Color.fieldLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            Spacer(minLength: DS.Spacing.sm)
            Toggle(L10n.t("يظهر عند فتح التطبيق", "Show when the app opens"), isOn: $isOn)
                .labelsHidden()
                .tint(DS.Color.toggleOn)
                .accessibilityLabel(L10n.t("يظهر عند فتح التطبيق", "Show when the app opens"))
        }
        .dsRowBox()
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .dsFieldFont(.label)
            .foregroundColor(DS.Color.fieldLabel)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: الصورة

    private var imageBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            label(L10n.t("الصورة", "Image"))
            if let image {
                HStack(alignment: .bottom, spacing: DS.Spacing.md) {
                    thumbnail(image)
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            DSAddChipLabel(icon: "photo", title: L10n.t("تغيير الصورة", "Change image"),
                                           isLoading: loadingImage)
                        }
                        .disabled(loadingImage)
                        Button {
                            withAnimation(DS.Anim.snappy) { self.image = nil; pickerItem = nil }
                        } label: {
                            Label(L10n.t("إزالة", "Remove"), systemImage: "trash")
                                .dsFont(.chip)
                                .foregroundColor(DS.Color.error)
                                .dsTapArea(width: DS.Icon.tapTarget, height: DS.Icon.tapTarget)
                        }
                        .buttonStyle(DSPressStyle())
                    }
                    Spacer(minLength: 0)
                }
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    DSAddChipLabel(icon: "photo.badge.plus", title: L10n.t("اختر صورة الإعلان", "Pick the announcement image"),
                                   fullWidth: true, isLoading: loadingImage)
                }
                .disabled(loadingImage)
            }
            Text(L10n.t("المقاس المناسب: 1080 × 1350 بكسل (طولي 4:5)", "Best size: 1080 × 1350 px (portrait 4:5)"))
                .dsFont(.caption)
                .foregroundColor(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// المصغّرة كما ستظهر: بطاقة ٤:٥ كحلية والصورة ملاءمة داخلها
    private func thumbnail(_ image: UIImage) -> some View {
        let width = DS.LaunchCard.composerThumbWidth
        let shape = RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
        return ZStack {
            shape.fill(DS.LaunchCard.fill)
            Image(uiImage: image).resizable().scaledToFit()
        }
        .frame(width: width, height: width / DS.LaunchCard.aspect)
        .clipShape(shape)
        .accessibilityElement()
        .accessibilityLabel(L10n.t("صورة الإعلان", "Announcement image"))
        .accessibilityAddTraits(.isImage)
    }

    private func loadImage(_ item: PhotosPickerItem) {
        loadingImage = true
        Task {
            // فكّ مصغّر خارج الخيط الرئيسي (مثل صور الأخبار)
            var loaded: UIImage? = nil
            if let data = try? await item.loadTransferable(type: Data.self) {
                loaded = await Task.detached(priority: .userInitiated) { ImageProcessor.downsampled(data) }.value
            }
            loadingImage = false
            if let loaded {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(DS.Anim.snappy) { image = loaded }
            }
        }
    }

    // MARK: لين

    private var durationBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            label(L10n.t("لين:", "Until:"))
            AdminChoiceRow {
                durationChip(.day, title: L10n.t("يوم", "1 day"))
                durationChip(.twoDays, title: L10n.t("يومين", "2 days"))
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(DS.Anim.snappy) {
                        if choice.duration == .until { dateOpen.toggle() } else { choice.duration = .until; dateOpen = true }
                    }
                } label: {
                    AdminChoiceChip(title: choice.duration == .until
                                        ? AdminOccasionsText.shortDate(choice.untilDay) : L10n.t("اختر تاريخاً", "Pick a date"),
                                    isSelected: choice.duration == .until, expands: true)
                }
                .buttonStyle(DSPressStyle())
                .accessibilityAddTraits(choice.duration == .until ? .isSelected : [])
            }
            if choice.duration == .until && dateOpen {
                DatePicker(L10n.t("التاريخ", "Date"), selection: $choice.untilDay,
                           in: Calendar.current.startOfDay(for: Date())..., displayedComponents: [.date])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .environment(\.locale, LanguageManager.shared.locale)
                    .dsRowBox()
                    .transition(.opacity)
            }
        }
    }

    private func durationChip(_ kind: AdminLaunchDuration, title: String) -> some View {
        Button {
            guard choice.duration != kind else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.snappy) { choice.duration = kind; dateOpen = false }
        } label: {
            AdminChoiceChip(title: title, isSelected: choice.duration == kind)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityAddTraits(choice.duration == kind ? .isSelected : [])
    }

    // MARK: الزر

    private var buttonBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            label(L10n.t("الزر:", "Button:"))
            AdminChoiceRow {
                buttonChip(.update, title: L10n.t("حدّث الآن ← المتجر", "Update now → Store"))
                buttonChip(.news, title: L10n.t("افتح الأخبار", "Open News"))
            }
            AdminChoiceRow {
                buttonChip(.link, title: L10n.t("رابط", "Link"), expands: true)
                buttonChip(.none, title: L10n.t("بدون زر", "No button"))
            }
            if choice.button == .link {
                DSComposerField(icon: "link", label: L10n.t("الرابط", "Link"),
                                placeholder: "https://…", text: $choice.link, tint: tint,
                                limit: 500, keyboard: .URL, ltr: true)
                    .transition(.opacity)
            }
        }
    }

    private func buttonChip(_ kind: LaunchAnnouncement.Kind, title: String, expands: Bool = false) -> some View {
        Button {
            guard choice.button != kind else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(DS.Anim.snappy) { choice.button = kind }
        } label: {
            AdminChoiceChip(title: title, isSelected: choice.button == kind, expands: expands)
        }
        .buttonStyle(DSPressStyle())
        .accessibilityAddTraits(choice.button == kind ? .isSelected : [])
    }
}
