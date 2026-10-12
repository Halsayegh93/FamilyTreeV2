import SwiftUI
import UIKit
import Photos
import PhotosUI
import ImageIO

/// حالة شاشة «بوستات المناسبات»: القالب، مكان النشر، الاختيارات، الاسم من الشجرة، الصورة، والتصدير.
/// النصوص تطلع من الاختيارات (OccasionCompose) — نفس منطق الموقع.
@MainActor
final class OccasionComposerViewModel: ObservableObject {
    @Published private(set) var template: OccasionTemplate
    @Published var placement: OccasionPlacement
    @Published var form = OccasionForm()
    /// العضو المختار من شجرة العائلة (رجال)
    @Published private(set) var member: FamilyMember?
    @Published var nameFormat: OccasionNameFormat = .three
    @Published var photo = OccasionPhoto()
    /// الصورة الحالية صورة العضو من الشجرة (مو صورة اختارها المستخدم)
    @Published private(set) var photoFromMember = false
    @Published private(set) var isLoadingMemberPhoto = false
    @Published private(set) var isWorking = false
    @Published var message: String?
    @Published var shareItem: OccasionShareItem?

    /// بيانات من القاعدة للاختيارات
    @Published private(set) var family = OccasionFamilyIndex([])
    @Published private(set) var diwaniyas: [Diwaniya] = []
    @Published private(set) var familyNames: [String] = []

    /// سطور القرابة اللي تعبّت تلقائياً من الشجرة — تتبدّل لو تغيّر العضو وما عدّلها المستخدم
    private var autoRelations: [String: String] = [:]
    private var avatarTask: Task<Void, Never>?

    let kit = OccasionKit.shared
    let templates = OccasionTemplate.all
    let placements = OccasionPlacement.all

    static let relationKeys = ["relation", "rel2", "rel3"]

    init() {
        template = OccasionTemplate.all[0]
        placement = OccasionPlacement.all[0]
    }

    var size: OccasionSize { placement.size }
    var gender: OccasionGender { form.gender }
    var isDeath: Bool { template.kind == .death || template.kind == .deathText }

    /// مفتاح الملفات المطلوبة — يتغيّر مع القالب أو المقاس
    var assetKey: String { "\(template.id)-\(size.rawValue)" }

    /// الاسم في البوست: من الشجرة بالصيغة المختارة، أو المكتوب
    var name: String {
        if let member { return nameFormat.apply(member) }
        return form.txt("nameTyped")
    }

    /// نصوص البوست النهائية
    var values: [String: String] { OccasionCompose.values(template, form, name: name) }

    // MARK: البيانات

    func updateFamily(_ all: [FamilyMember]) {
        family = OccasionFamilyIndex(all)
        // العضو المختار يتحدّث لو تغيّرت بياناته
        if let m = member, let fresh = family.byId[m.id] { member = fresh }
    }

    func updateDiwaniyas(_ list: [Diwaniya]) {
        diwaniyas = list.filter { $0.approvalStatus == ApprovalStatus.approved.rawValue && $0.isClosed != true }
    }

    func updateFamilyNames(_ names: [String]) {
        familyNames = names
    }

    // MARK: الاختيارات

    func sel(_ key: String) -> Int { form.sel(key) }

    func setSel(_ key: String, _ index: Int) { form.selections[key] = index }

    func text(_ key: String) -> Binding<String> {
        Binding(get: { [weak self] in self?.form.txt(key) ?? "" },
                set: { [weak self] in self?.form.texts[key] = $0 })
    }

    /// مكان العزاء: لو كان ديوانية معتمدة، تتعبّى المنطقة من عنوانها
    func venuePlace(_ side: String) -> Binding<String> {
        Binding(get: { [weak self] in self?.form.txt("\(side)Place") ?? "" },
                set: { [weak self] value in
                    guard let self else { return }
                    self.form.texts["\(side)Place"] = value
                    if let d = self.diwaniyas.first(where: { $0.title == value }),
                       let area = OccasionChoices.area(inAddress: d.address) {
                        self.form.texts["\(side)Area"] = area
                    }
                })
    }

    func setGender(_ next: OccasionGender) {
        guard next != form.gender else { return }
        // أسماء الشجرة (جدول الأعضاء) للرجال — للمؤنث نكتب الاسم
        if next == .female, member != nil { clearMember() }
        form.gender = next
    }

    func select(_ next: OccasionTemplate) {
        guard next.id != template.id else { return }
        template = next
        // اختيارات خاصة بكل قالب (قوائمها تختلف) ترجع للأول
        for key in ["opening", "occasion", "dua"] { form.selections[key] = nil }
        photo.gray = next.kind == .death
    }

    /// يبدأ من جديد (يحتفظ بالقالب ومكان النشر)
    func resetForm() {
        let keepGray = photo.gray
        avatarTask?.cancel()
        isLoadingMemberPhoto = false
        form = OccasionForm()
        member = nil
        autoRelations = [:]
        nameFormat = .three
        if photoFromMember {
            photo = OccasionPhoto(gray: keepGray)
            photoFromMember = false
        }
    }

    // MARK: الاسم من الشجرة

    func pickMember(_ m: FamilyMember) {
        member = m
        let sons = family.sonsLine(m)
        let next: [String: String] = [
            "relation": sons.isEmpty ? family.fatherLine(m) : sons,
            "rel2": sons,
            "rel3": family.brothersLine(m),
        ]
        // نعبّي الفاضي أو اللي تعبّى تلقائياً من عضو سابق — اللي كتبه المستخدم ما نلمسه
        for key in Self.relationKeys {
            let current = form.txt(key)
            if current.isEmpty || current == autoRelations[key] { form.texts[key] = next[key] ?? "" }
        }
        autoRelations = next
        form.gender = .male

        // صورة العضو السابق تنشال فوراً (حتى ما يطلع اسم عضو بصورة عضو ثاني لو فشل التحميل)
        if photoFromMember {
            photo = OccasionPhoto(gray: photo.gray)
            photoFromMember = false
        }
        let url = (m.avatarUrl ?? "").isEmpty ? nil : URL(string: m.avatarUrl ?? "")
        if let url, photo.image == nil {
            loadMemberPhoto(url, memberId: m.id)
        } else {
            // صورة اختارها المستخدم بنفسه تبقى
            avatarTask?.cancel()
            isLoadingMemberPhoto = false
        }
    }

    func clearMember() {
        member = nil
        for key in Self.relationKeys {
            if let auto = autoRelations[key], !auto.isEmpty, form.txt(key) == auto { form.texts[key] = "" }
        }
        autoRelations = [:]
        avatarTask?.cancel()
        isLoadingMemberPhoto = false
        if photoFromMember {
            photo = OccasionPhoto(gray: photo.gray)
            photoFromMember = false
        }
    }

    /// سطور مقترحة من الشجرة للعضو المختار
    var relationSuggestions: [String] {
        guard let m = member else { return [] }
        return [family.sonsLine(m), family.fatherLine(m), family.brothersLine(m)].filter { !$0.isEmpty }
    }

    var sonsSuggestion: [String] {
        guard let m = member else { return [] }
        let line = family.sonsLine(m)
        return line.isEmpty ? [] : [line]
    }

    var brothersSuggestion: [String] {
        guard let m = member else { return [] }
        let line = family.brothersLine(m)
        return line.isEmpty ? [] : [line]
    }

    /// أبناء العضو (الأحدث أولاً) — اقتراحات اسم المولود
    var babyNameSuggestions: [String] {
        guard let m = member, template.id == "newborn" else { return [] }
        return family.childrenNewestFirst(m.id).prefix(6).map { OccasionFamilyIndex.firstName($0) }
    }

    private func loadMemberPhoto(_ url: URL, memberId: UUID) {
        avatarTask?.cancel()
        isLoadingMemberPhoto = true
        avatarTask = Task { [weak self] in
            // التنزيل وفك الصورة خارج الخيط الرئيسي
            let image = await Task.detached(priority: .userInitiated) {
                await Self.fetchImage(url, maxPixel: 1600)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isLoadingMemberPhoto = false
            // العضو تغيّر، أو المستخدم اختار صورة بنفسه أثناء التحميل
            guard self.member?.id == memberId, self.photo.image == nil || self.photoFromMember else { return }
            guard let image else {
                self.message = L10n.t("ما قدرنا نحمّل صورة العضو — تقدر تختار صورة بنفسك.",
                                      "Couldn't load the member's photo — you can choose one yourself.")
                return
            }
            // أبيض وأسود حسب القالب الحالي (اختيار القالب يضبطه)
            self.photo = OccasionPhoto(image: image, zoom: 1, x: 50, y: 40, gray: self.photo.gray)
            self.photoFromMember = true
        }
    }

    nonisolated private static func fetchImage(_ url: URL, maxPixel: Int) async -> UIImage? {
        guard let result = try? await URLSession.shared.data(from: url),
              let http = result.1 as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return downscaled(result.0, maxPixel: maxPixel)
    }

    func prepareAssets() async {
        await kit.prepare(template.assetPaths(for: size))
    }

    // MARK: الصورة

    func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = await Task.detached(priority: .userInitiated, operation: { Self.downscaled(data, maxPixel: 1600) }).value else {
                message = L10n.t("ما قدرنا نفتح الصورة — جرّب صورة ثانية.", "Couldn't open the photo — try another one.")
                return
            }
            avatarTask?.cancel()
            isLoadingMemberPhoto = false
            photo.image = image
            photo.zoom = 1
            photo.x = 50
            photo.y = 40
            photoFromMember = false
        } catch {
            Log.error("Occasion photo load failed: \(error.localizedDescription)")
            message = L10n.t("ما قدرنا نفتح الصورة — جرّب صورة ثانية.", "Couldn't open the photo — try another one.")
        }
    }

    func removePhoto() {
        avatarTask?.cancel()
        isLoadingMemberPhoto = false
        photo.image = nil
        photo.zoom = 1
        photo.x = 50
        photo.y = 40
        photoFromMember = false
    }

    /// يصغّر الصورة ويثبّت اتجاهها بدون فك الصورة الأصلية كاملة في الذاكرة
    /// (الصورة تبقى على الجهاز — ما تنرفع لأي مكان)
    nonisolated private static func downscaled(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: التصدير

    /// يرسم البوست بمقاسه الحقيقي (1080 × الارتفاع) بكسل
    func render() async -> UIImage? {
        guard await kit.prepare(template.assetPaths(for: size)), kit.fontsReady else { return nil }
        let view = OccasionPostView(template: template, size: size, values: values, photo: photo, kit: kit, revision: kit.revision)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(size.canvas)
        renderer.scale = 1
        return renderer.uiImage
    }

    func saveToPhotos() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let image = await render(), let data = image.pngData() else {
            message = renderFailedMessage
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = L10n.t("اسمح للتطبيق بإضافة الصور من الإعدادات ← الخصوصية ← الصور.",
                             "Allow the app to add photos in Settings → Privacy → Photos.")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            }
            message = L10n.t("انحفظ البوست في الصور ✓", "Saved to Photos ✓")
        } catch {
            Log.error("Occasion save to Photos failed: \(error.localizedDescription)")
            message = L10n.t("ما انحفظت الصورة — حاول مرة ثانية.", "Couldn't save the image — please try again.")
        }
    }

    func share() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        guard let image = await render(), let data = image.pngData() else {
            message = renderFailedMessage
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("almohali-\(template.id)-\(size.rawValue).png")
        do {
            try data.write(to: url, options: .atomic)
            shareItem = OccasionShareItem(url: url)
        } catch {
            Log.error("Occasion share file write failed: \(error.localizedDescription)")
            message = renderFailedMessage
        }
    }

    private var renderFailedMessage: String {
        kit.failed
            ? L10n.t("تعذّر تحميل ملفات التصميم — تأكد من الاتصال وحاول مرة ثانية.", "Couldn't download the design files — check your connection and try again.")
            : L10n.t("صار خطأ أثناء تجهيز الصورة — حاول مرة ثانية.", "Something went wrong while preparing the image — please try again.")
    }
}

struct OccasionShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
