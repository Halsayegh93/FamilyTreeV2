import Foundation
import Supabase

// الصور الخاصة — المرحلة ١ (٢٠٢٦-١٠-١٩): كل ملف من Supabase Storage يُعرض/يُنزَّل عبر هذا المحلِّل.
// القاعدة تحفظ الرابط العام كما هو (…/object/public/<bucket>/<path>?v=…) والرفع لم يتغيّر.
// المحلِّل يطلب رابطاً موقَّعاً بجلسة المستخدم، وإن فشل التوقيع (لا جلسة / لا شبكة / خطأ) يرجع للرابط
// الأصلي — فالتطبيق يعمل اليوم (المستودعات عامّة) كما كان، ويعمل بعد جعلها خاصّة (المرحلة ٢).

// MARK: - StorageObjectRef (Foundation فقط — يُختبر منفصلاً)

/// هوية ملف في Storage: المستودع + المسار + رقم النسخة `?v=` (إن وُجد).
nonisolated struct StorageObjectRef: Hashable, Sendable {
    let bucket: String
    /// اسم الملف داخل المستودع (غير مُرمَّز) — مثل `abc.jpg` أو `news/<author>/<id>.jpg`
    let path: String
    /// رقم النسخة من الرابط المحفوظ (`?v=`) — يتغيّر عند استبدال الصورة بنفس المسار
    let version: String?

    /// المستودعات المعروفة — شرط لقبول مسار مجرّد بلا نطاق (`<bucket>/<path>`)
    static let knownBuckets: Set<String> = ["avatars", "family-archive", "family-gallery", "gallery", "news", "stories"]

    private static let urlMarkers = [
        "/storage/v1/object/public/",
        "/storage/v1/object/sign/",
        "/storage/v1/object/authenticated/",
    ]

    /// `bucket/path?v=…` — الهوية الثابتة للصورة (مفتاح الروابط الموقَّعة والكاش). لا يدخل فيه التوقيع أبداً.
    var cacheKey: String {
        guard let version else { return "\(bucket)/\(path)" }
        return "\(bucket)/\(path)?v=\(version)"
    }

    /// الرابط العام لنفس الملف (`<project>/storage/v1/object/public/<bucket>/<path>?v=`)
    func publicURL(base: URL) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + "/storage/v1/object/public/\(bucket)/\(path)"
        components.queryItems = version.map { [URLQueryItem(name: "v", value: $0)] }
        return components.url
    }

    /// يحلّل القيمة المحفوظة. يقبل: رابط `public` / `sign` / `authenticated` على نطاق المشروع،
    /// أو مساراً مجرّداً `<bucket>/<path>[?v=…]` لمستودع معروف. غير ذلك (خرائط، مواقع، ملفات الحزمة
    /// على app.almohali.com…) → nil ويمرّ الرابط كما هو.
    static func parse(_ stored: String, projectHost: String?) -> StorageObjectRef? {
        let raw = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        if raw.contains("://") {
            guard let components = URLComponents(string: raw)
                    ?? raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap({ URLComponents(string: $0) }),
                  let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
                  let host = components.host?.lowercased()
            else { return nil }
            if let projectHost, host != projectHost.lowercased() { return nil }
            let path = components.path // غير مُرمَّز
            guard let marker = urlMarkers.first(where: { path.hasPrefix($0) }) else { return nil }
            return make(rest: String(path.dropFirst(marker.count)), query: components.queryItems, knownBucketsOnly: false)
        }

        // مسار مجرّد
        let pieces = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(pieces[0])
        let query = pieces.count > 1 ? URLComponents(string: "?" + pieces[1])?.queryItems : nil
        return make(rest: pathPart.removingPercentEncoding ?? pathPart, query: query, knownBucketsOnly: true)
    }

    private static func make(rest: String, query: [URLQueryItem]?, knownBucketsOnly: Bool) -> StorageObjectRef? {
        let trimmed = rest.drop(while: { $0 == "/" })
        guard let slash = trimmed.firstIndex(of: "/") else { return nil }
        let bucket = String(trimmed[..<slash])
        let path = String(trimmed[trimmed.index(after: slash)...])
        guard !bucket.isEmpty, !path.isEmpty else { return nil }
        if knownBucketsOnly, !knownBuckets.contains(bucket) { return nil }
        let version = query?.first(where: { $0.name == "v" })?.value.flatMap { $0.isEmpty ? nil : $0 }
        return StorageObjectRef(bucket: bucket, path: path, version: version)
    }
}

// MARK: - Resolver

/// المكان الوحيد الذي يحوّل رابط Storage المحفوظ إلى رابط عرض.
/// - روابط موقَّعة لساعة، تُعاد استعمالها ~٥٠ دقيقة (المفتاح `bucket/path?v=`).
/// - الطلبات المتزامنة (قائمة/شجرة/ألبوم تُرسم دفعة واحدة) تُجمَع تلقائياً في طلب توقيع واحد لكل مستودع.
/// - فشل التوقيع → الرابط الأصلي، ولا إعادة محاولة لنفس الملف قبل دقيقتين.
@MainActor
final class StorageURLResolver {
    static let shared = StorageURLResolver()

    private static let signSeconds = 3600
    private static let reuseFor: TimeInterval = 50 * 60
    private static let retryAfterFailure: TimeInterval = 2 * 60
    private static let batchDelay: Duration = .milliseconds(25)
    private static let maxBatch = 100

    private let projectBase = SupabaseConfig.url
    private var signed: [String: (url: URL, until: Date)] = [:]
    private var failedUntil: [String: Date] = [:]
    private var waiters: [String: [CheckedContinuation<URL?, Never>]] = [:]
    private var queued: [String: [StorageObjectRef]] = [:]
    private var flushScheduled = false
    /// يزيد مع `reset()` — نتائج دفعة بدأت قبل الخروج لا تُحفَظ
    private var generation = 0
    /// وجود الجلسة يُقرأ من التخزين — نتيجته تُحفَظ ثوانيَ قليلة (لا قراءة لكل صورة في قائمة طويلة)
    private var sessionCheckedAt = Date.distantPast
    private var hasSession = false

    private init() {}

    func ref(for stored: String) -> StorageObjectRef? {
        StorageObjectRef.parse(stored, projectHost: projectBase.host)
    }

    /// مفتاح كاش الصور: للملفات = الرابط العام القانوني (دالّة في `bucket/path?v=` وحدها، ويطابق
    /// المفتاح القديم فلا يُعاد تنزيل ما في الكاش)؛ لغيرها = الرابط نفسه.
    func cacheKeyURL(for url: URL) -> URL {
        guard let ref = ref(for: url.absoluteString) else { return url }
        return ref.publicURL(base: projectBase) ?? url
    }

    /// رابط العرض لقيمة محفوظة (موقَّع إن أمكن، وإلا الأصلي).
    func displayURL(for stored: String) async -> URL? {
        let raw = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ref = ref(for: raw) else { return URL(string: raw) }
        return await signedURL(for: ref) ?? fallbackURL(original: URL(string: raw), ref: ref)
    }

    func displayURL(for url: URL) async -> URL {
        guard let ref = ref(for: url.absoluteString) else { return url }
        return await signedURL(for: ref) ?? fallbackURL(original: url, ref: ref) ?? url
    }

    /// رابط موقَّع فشل تنزيله (انتهى مبكراً مثلاً) — يُرمى ليُوقَّع من جديد في المرة القادمة
    func invalidate(_ url: URL) {
        guard let ref = ref(for: url.absoluteString) else { return }
        signed[ref.cacheKey] = nil
    }

    /// عند تسجيل الخروج
    func reset() {
        generation += 1
        signed.removeAll()
        failedUntil.removeAll()
        sessionCheckedAt = .distantPast
    }

    // MARK: داخلي

    /// الرجوع: الرابط العام الأصلي كما حُفظ؛ رابط `sign` قديم أو مسار مجرّد → الرابط العام القانوني
    private func fallbackURL(original: URL?, ref: StorageObjectRef) -> URL? {
        if let original, original.scheme != nil, original.path.contains("/object/public/") { return original }
        return ref.publicURL(base: projectBase) ?? original
    }

    private func signedURL(for ref: StorageObjectRef) async -> URL? {
        let key = ref.cacheKey
        let now = Date()
        if let hit = signed[key], hit.until > now { return hit.url }
        if let until = failedUntil[key], until > now { return nil }
        // بلا جلسة (شاشة الدخول/التسجيل) — الرابط الأصلي مباشرة
        guard sessionAvailable(now) else { return nil }
        return await withCheckedContinuation { continuation in
            if waiters[key] != nil {
                waiters[key]?.append(continuation)
                return
            }
            waiters[key] = [continuation]
            queued[ref.bucket, default: []].append(ref)
            scheduleFlush()
        }
    }

    private func sessionAvailable(_ now: Date) -> Bool {
        if now.timeIntervalSince(sessionCheckedAt) > 5 {
            hasSession = SupabaseConfig.client.auth.currentSession != nil
            sessionCheckedAt = now
        }
        return hasSession
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: Self.batchDelay)
            self.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        let batches = queued
        queued.removeAll()
        let gen = generation
        for (bucket, refs) in batches {
            for start in stride(from: 0, to: refs.count, by: Self.maxBatch) {
                let chunk = Array(refs[start..<min(start + Self.maxBatch, refs.count)])
                Task { await self.sign(chunk, bucket: bucket, generation: gen) }
            }
        }
    }

    private func sign(_ refs: [StorageObjectRef], bucket: String, generation gen: Int) async {
        var paths: [String] = []
        for ref in refs where !paths.contains(ref.path) { paths.append(ref.path) }
        var results: [String: URL] = [:]
        do {
            results = try await requestSignedURLs(bucket: bucket, paths: paths)
        } catch {
            Log.warning("[Storage] تعذّر التوقيع (\(bucket), \(paths.count)) — الرابط الأصلي: \(error.localizedDescription)")
        }
        let now = Date()
        for ref in refs {
            let key = ref.cacheKey
            let url = results[ref.path]
            if gen == generation {
                if let url {
                    signed[key] = (url, now.addingTimeInterval(Self.reuseFor))
                    failedUntil[key] = nil
                } else {
                    failedUntil[key] = now.addingTimeInterval(Self.retryAfterFailure)
                }
            }
            for continuation in waiters.removeValue(forKey: key) ?? [] {
                continuation.resume(returning: url)
            }
        }
    }

    private struct SignedItem: Decodable {
        let path: String?
        let signedURL: String?
    }

    /// `createSignedUrls` — نفس نقطة `POST /object/sign/<bucket>` التي تستعملها المكتبة، لكن بقراءة كل عنصر
    /// على حدة: `createSignedURLs` في supabase-swift يرمي الدفعة كلها إن كان ملف واحد مفقوداً.
    private func requestSignedURLs(bucket: String, paths: [String]) async throws -> [String: URL] {
        let client = SupabaseConfig.client
        let token = try await client.auth.session.accessToken
        let storage = client.storage.configuration
        var request = URLRequest(url: storage.url.appendingPathComponent("object/sign/\(bucket)"))
        request.httpMethod = "POST"
        for (name, value) in storage.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": Self.signSeconds, "paths": paths])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let items = try JSONDecoder().decode([SignedItem].self, from: data)
        var out: [String: URL] = [:]
        for (index, item) in items.enumerated() {
            guard let relative = item.signedURL, !relative.isEmpty,
                  let url = Self.absoluteSignedURL(relative, storageBase: storage.url),
                  let path = items.count == paths.count ? paths[index] : item.path
            else { continue }
            out[path] = url
        }
        return out
    }

    /// الخادم يرجع `/object/sign/<bucket>/<path>?token=…` نسبةً إلى `<project>/storage/v1`
    private static func absoluteSignedURL(_ relative: String, storageBase: URL) -> URL? {
        if relative.lowercased().hasPrefix("http") { return URL(string: relative) }
        var base = storageBase.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + (relative.hasPrefix("/") ? relative : "/" + relative))
    }
}
