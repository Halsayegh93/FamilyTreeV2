import Foundation

/// رفع ملفات «المكتبة» (طلب المالك ٢٠٢٦-١١-١٤ «١٠٠ ميغا… بشكل ما يخترب»):
/// - الحدّ من السيرفر: `app_config.library_max_upload_mb` (٥…١٠٠)، وغيابه = ٢٥ (سلوك النسخ السابقة)؛
///   مشغّل على السيرفر يُبقي حدّ مستودع `family-archive` مطابقاً له (20261114180000).
/// - ما فوق ٦ ميغابايت يُرفع بالرفع المستأنَف (TUS) قطعاً بحجم ٦ ميغابايت بالضبط من القرص — لا يُحمَّل الملف كله
///   في الذاكرة، وكل قطعة تُعاد حتى ٣ مرات (HEAD يعرف أين وقف السيرفر). ≤ ٦ ميغابايت = الرفع البسيط كما كان.
/// ملف بلا اعتماد على SwiftUI/Supabase — يُفحص بلا محاكي: `tests/library-upload/main.swift`.
enum LibraryUpload {
    /// مفتاح الحدّ في `app_config()`
    static let configKey = "library_max_upload_mb"
    /// الحدّ حين لا يصل المفتاح (قبل تطبيق الترحيل أو فشل الجلب) — حدّ المستودع القديم
    static let fallbackMB = 25
    static let minMB = 5
    static let maxMB = 100
    /// حجم القطعة — يشترطه Supabase للرفع المستأنَف (٦ ميغابايت بالضبط)
    static let chunkSize = 6 * 1024 * 1024
    /// محاولات كل قطعة قبل الفشل
    static let chunkAttempts = 3

    /// الحدّ بالميغابايت من قيمة السيرفر الخام (nil = غائب ← ٢٥)، محصوراً في ٥…١٠٠
    static func limitMB(fromConfig raw: Int?) -> Int {
        guard let raw else { return fallbackMB }
        return min(max(raw, minMB), maxMB)
    }

    static func maxBytes(mb: Int) -> Int64 { Int64(mb) * 1024 * 1024 }

    /// فوق ٦ ميغابايت → الرفع المستأنَف
    static func usesResumable(size: Int64) -> Bool { size > Int64(chunkSize) }

    /// مدى كل قطعة (البداية والطول) لملف بحجم `total`
    static func chunks(total: Int64, chunkSize: Int = chunkSize) -> [(offset: Int64, length: Int)] {
        guard total > 0, chunkSize > 0 else { return [] }
        var out: [(Int64, Int)] = []
        var offset: Int64 = 0
        while offset < total {
            let length = Int(min(Int64(chunkSize), total - offset))
            out.append((offset, length))
            offset += Int64(length)
        }
        return out
    }

    /// أرقام عربية مشرقية (مثل «٢٥» في الرسالة القديمة)
    static func arabicDigits(_ n: Int) -> String {
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤",
                                           "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(String(n).map { map[$0] ?? $0 })
    }

    /// «الملف أكبر من N ميغابايت…» بالحدّ الحيّ
    static func tooLargeText(mb: Int, arabic: Bool) -> String {
        arabic
            ? "الملف أكبر من \(arabicDigits(mb)) ميغابايت — اختر ملفاً أصغر أو صورة مضغوطة."
            : "The file is larger than \(mb) MB — choose a smaller file or a compressed photo."
    }

    /// تلميح منتقي الملف: «صورة أو PDF · حتى N ميغابايت»
    static func pickerHint(mb: Int, arabic: Bool) -> String {
        arabic ? "صورة أو PDF · حتى \(arabicDigits(mb)) ميغابايت" : "Photo or PDF · up to \(mb) MB"
    }

    /// رسالة فشل الرفع الموحّدة (صياغة رسمية)
    static func failureText(arabic: Bool) -> String {
        arabic ? "تعذّر رفع الملف. تحقّق من الاتصال وحاول مرة أخرى."
               : "Couldn't upload the file. Check your connection and try again."
    }

    /// نقطة الرفع المستأنَف: `<ref>.supabase.co` ← `<ref>.storage.supabase.co` (المضيف المباشر للتخزين —
    /// توصية Supabase للملفات الكبيرة)، وأي عنوان آخر ← `<url>/storage/v1/upload/resumable`
    static func resumableEndpoint(projectURL: URL) -> URL {
        if var comps = URLComponents(url: projectURL, resolvingAgainstBaseURL: false),
           let host = comps.host, host.hasSuffix(".supabase.co"), !host.hasSuffix(".storage.supabase.co") {
            let ref = host.dropLast(".supabase.co".count)
            comps.host = "\(ref).storage.supabase.co"
            comps.path = "/storage/v1/upload/resumable"
            if let url = comps.url { return url }
        }
        return projectURL.appendingPathComponent("storage/v1/upload/resumable")
    }

    /// ترويسة `Upload-Metadata`: مفتاح ثم قيمة base64، مفصولة بفواصل
    static func uploadMetadata(bucket: String, objectName: String, contentType: String,
                               cacheControl: String = "3600") -> String {
        [("bucketName", bucket), ("objectName", objectName),
         ("contentType", contentType), ("cacheControl", cacheControl)]
            .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
            .joined(separator: ",")
    }
}

// MARK: - مصدر الملف

/// الملف المرفوع: بيانات في الذاكرة (صورة معاد ترميزها) أو ملف على القرص (PDF — يُقرأ قطعة قطعة)
enum LibraryUploadSource: Sendable {
    case data(Data)
    case file(URL)

    var size: Int64 {
        switch self {
        case .data(let d): return Int64(d.count)
        case .file(let url):
            let n = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
            return n ?? 0
        }
    }

    /// قطعة من الملف — الملف يُفتح ويُغلق لكل قطعة فلا يبقى في الذاكرة إلا ٦ ميغابايت
    func read(offset: Int64, length: Int) throws -> Data {
        switch self {
        case .data(let d):
            let start = Int(offset)
            let end = min(d.count, start + length)
            return d.subdata(in: start..<end)
        case .file(let url):
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length) ?? Data()
        }
    }

    /// الملف كاملاً — للرفع البسيط (≤ ٦ ميغابايت) فقط
    func readAll() throws -> Data {
        switch self {
        case .data(let d): return d
        case .file(let url): return try Data(contentsOf: url)
        }
    }
}

// MARK: - الرفع المستأنَف (TUS 1.0.0)

enum TusUploadError: Error, LocalizedError {
    case http(Int, String)
    case missingLocation
    case offsetMismatch

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "TUS HTTP \(code): \(body)"
        case .missingLocation: return "TUS: no Location header"
        case .offsetMismatch: return "TUS: offset mismatch"
        }
    }
}

/// عميل TUS صغير لـ Supabase Storage: POST ينشئ الرفع ← PATCH لكل قطعة بـ`Upload-Offset` ← عند الفشل HEAD
/// لمعرفة ما وصل ثم إعادة القطعة (حتى ٣ مرات). الإلغاء (`Task.cancel`) يوقف الطلب الجاري فوراً.
struct TusUploader: Sendable {
    let endpoint: URL
    let apiKey: String
    let bucket: String
    let objectName: String
    let contentType: String
    var cacheControl: String = "3600"
    var upsert: Bool = false
    var extraHeaders: [String: String] = [:]
    /// رمز المستخدم — يُطلب قبل كل طلب (يتجدّد الرمز أثناء رفع طويل)
    let accessToken: @Sendable () async throws -> String

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        return URLSession(configuration: configuration)
    }()

    /// يرفع المصدر كاملاً؛ `progress` بين ٠ و١ (بايتات وصلت السيرفر)
    func upload(_ source: LibraryUploadSource, progress report: @escaping @Sendable (Double) -> Void) async throws {
        let total = source.size
        // لا تبليغ لكل حزمة — كل ٠٫٥٪ على الأكثر
        let gate = ProgressGate(step: 0.005)
        let progress: @Sendable (Double) -> Void = { if gate.pass($0) { report($0) } }
        let location = try await create(total: total)
        var offset: Int64 = 0
        progress(0)
        while offset < total {
            try Task.checkCancellation()
            var attempt = 0
            while offset < total {
                attempt += 1
                do {
                    // الطول يُحسب في كل محاولة — بعد HEAD قد تبدأ القطعة من موضع آخر
                    let length = Int(min(Int64(LibraryUpload.chunkSize), total - offset))
                    let chunk = try source.read(offset: offset, length: length)
                    let base = offset
                    offset = try await patch(location, offset: offset, chunk: chunk) { sent in
                        progress(Double(base + sent) / Double(total))
                    }
                    progress(Double(offset) / Double(total))
                    break
                } catch {
                    if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                        throw CancellationError()
                    }
                    if case TusUploadError.http(let code, _) = error, (400..<500).contains(code),
                       ![408, 409, 423, 429].contains(code) {
                        throw error   // رفض نهائي (صلاحية، حجم، نوع) — لا فائدة من الإعادة
                    }
                    guard attempt < LibraryUpload.chunkAttempts else { throw error }
                    try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                    // أين وقف السيرفر؟ قد يكون استلم جزءاً من القطعة
                    if let serverOffset = try? await head(location) { offset = serverOffset }
                }
            }
        }
        progress(1)
    }

    private func baseRequest(_ url: URL, method: String) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (k, v) in extraHeaders { request.setValue(v, forHTTPHeaderField: k) }
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(upsert ? "true" : "false", forHTTPHeaderField: "x-upsert")
        return request
    }

    private func create(total: Int64) async throws -> URL {
        var request = try await baseRequest(endpoint, method: "POST")
        request.setValue(String(total), forHTTPHeaderField: "Upload-Length")
        request.setValue(LibraryUpload.uploadMetadata(bucket: bucket, objectName: objectName,
                                                     contentType: contentType, cacheControl: cacheControl),
                         forHTTPHeaderField: "Upload-Metadata")
        let (body, response) = try await Self.session.data(for: request)
        let http = try Self.checked(response, body, ok: [201])
        guard let raw = http.value(forHTTPHeaderField: "Location"),
              let location = URL(string: raw, relativeTo: endpoint)?.absoluteURL else {
            throw TusUploadError.missingLocation
        }
        return location
    }

    private func patch(_ location: URL, offset: Int64, chunk: Data,
                       sent: @escaping @Sendable (Int64) -> Void) async throws -> Int64 {
        var request = try await baseRequest(location, method: "PATCH")
        request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        let delegate = TusProgressDelegate(onSent: sent)
        let (body, response) = try await Self.session.upload(for: request, from: chunk, delegate: delegate)
        let http = try Self.checked(response, body, ok: [200, 204])
        guard let next = http.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int64.init) else {
            return offset + Int64(chunk.count)
        }
        guard next > offset else { throw TusUploadError.offsetMismatch }
        return next
    }

    private func head(_ location: URL) async throws -> Int64 {
        var request = try await baseRequest(location, method: "HEAD")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (body, response) = try await Self.session.data(for: request)
        let http = try Self.checked(response, body, ok: [200, 204])
        guard let n = http.value(forHTTPHeaderField: "Upload-Offset").flatMap(Int64.init) else {
            throw TusUploadError.offsetMismatch
        }
        return n
    }

    private static func checked(_ response: URLResponse, _ body: Data, ok: Set<Int>) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else { throw TusUploadError.http(0, "") }
        guard ok.contains(http.statusCode) else {
            throw TusUploadError.http(http.statusCode, String(decoding: body.prefix(300), as: UTF8.self))
        }
        return http
    }
}

/// يمرّر التقدّم حين يتغيّر بقدر `step` (أو يكتمل) — آمن من أي خيط
private final class ProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    let step: Double
    init(step: Double) { self.step = step }
    func pass(_ value: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value >= 1 || value - last >= step || value < last else { return false }
        last = value
        return true
    }
}

/// تقدّم القطعة الجارية (بايتات أُرسلت) — لشريط يتحرّك داخل القطعة لا كل ٦ ميغابايت
private final class TusProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onSent: @Sendable (Int64) -> Void
    init(onSent: @escaping @Sendable (Int64) -> Void) { self.onSent = onSent }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onSent(totalBytesSent)
    }
}
