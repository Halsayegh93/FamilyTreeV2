import UserNotifications
import UniformTypeIdentifiers

// MARK: - «صورة الإشعار» (موافقة المالك ٢٠٢٦-١١-٢٥، الخيار ب «زر صورة خاص بالإشعار»)
//
// امتداد خدمة الإشعارات: يعمل فقط حين يحمل الإشعار `mutable-content: 1` — والدالة الطرفية `push-on-notification` لا تضعه
// إلا مع `image_url` (رابط موقّع من مستودع الأخبار الخاص). ينزّل الصورة (مهلة قصيرة أقل بكثير من ٣٠ ثانية النظام)،
// ويحفظها في ملف مؤقّت بامتدادها الصحيح، ويرفقها بالإشعار. أي فشل أو انتهاء الوقت ← الإشعار نصّاً كما كان.

final class NotificationService: UNNotificationServiceExtension {
    /// مهلة الطلب والتنزيل كاملاً — النظام يعطي الامتداد نحو ٣٠ ثانية
    private static let requestTimeout: TimeInterval = 10
    private static let resourceTimeout: TimeInterval = 20

    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var downloadTask: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        lock.lock()
        self.contentHandler = contentHandler
        self.bestAttempt = content
        lock.unlock()

        guard let raw = content.userInfo["image_url"] as? String,
              let url = URL(string: raw), url.scheme == "https" else {
            deliver(attachment: nil)
            return
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Self.requestTimeout
        config.timeoutIntervalForResource = Self.resourceTimeout
        config.waitsForConnectivity = false
        let session = URLSession(configuration: config)
        let task = session.downloadTask(with: url) { [weak self] location, response, error in
            // الملف المؤقّت يُحذف بعد رجوع هذا المعالج — يُنقل هنا مباشرة
            var attachment: UNNotificationAttachment? = nil
            if error == nil, let location,
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                attachment = Self.makeAttachment(from: location, mimeType: http.mimeType, url: url)
            }
            self?.deliver(attachment: attachment)
            session.finishTasksAndInvalidate()
        }
        lock.lock()
        downloadTask = task
        lock.unlock()
        task.resume()
    }

    /// الوقت يكاد ينتهي — الإشعار نصّاً بلا صورة
    override func serviceExtensionTimeWillExpire() {
        lock.lock()
        let task = downloadTask
        lock.unlock()
        task?.cancel()
        deliver(attachment: nil)
    }

    /// يسلّم الإشعار مرة واحدة فقط (التنزيل وانتهاء الوقت قد يتسابقان)
    private func deliver(attachment: UNNotificationAttachment?) {
        lock.lock()
        let handler = contentHandler
        let content = bestAttempt
        contentHandler = nil
        lock.unlock()
        guard let handler, let content else { return }
        if let attachment { content.attachments = [attachment] }
        handler(content)
    }

    /// ينقل الصورة إلى ملف مؤقّت بامتداد نوعها (jpg/png/gif — ما يقبله النظام) ويصنع المرفق
    private static func makeAttachment(from location: URL, mimeType: String?, url: URL) -> UNNotificationAttachment? {
        let type = mimeType.flatMap { UTType(mimeType: $0) }
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .jpeg
        let supported: [UTType] = [.jpeg, .png, .gif]
        guard supported.contains(where: { type.conforms(to: $0) }) else { return nil }
        let ext = type.preferredFilenameExtension ?? "jpg"
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("push-image-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("image").appendingPathExtension(ext)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: file)
            return try UNNotificationAttachment(identifier: "image", url: file,
                                                options: [UNNotificationAttachmentOptionsTypeHintKey: type.identifier])
        } catch {
            try? FileManager.default.removeItem(at: dir)
            return nil
        }
    }
}
