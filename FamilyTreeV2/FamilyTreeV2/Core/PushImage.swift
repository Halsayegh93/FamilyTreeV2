import UIKit
import Supabase

// MARK: - «صورة الإشعار» (موافقة المالك ٢٠٢٦-١١-٢٥، الخيار ب «زر صورة خاص بالإشعار»)
//
// صورة اختيارية في «إنشاء ← إعلان» تظهر داخل إشعار الجوال (شاشة القفل والشريط) — منفصلة عن صورة «الإعلان عند الفتح».
// المسار: الرفع هنا إلى `news/push/<uuid>.jpg` (رفع الإدارة في مستودع الأخبار مسموح أصلاً بسياسة `news_insert_admin`)
// ← `details.image_path` في صفّ الإشعار (أو الإشعار المجدول) ← مشغّل الدفع يمرّره ← `push-on-notification` يوقّع رابطاً
// (المستودع خاص) ويضعه في `image_url` مع `mutable-content` ← امتداد `NotificationService` في الآيفون ينزّلها ويرفقها.

enum PushImageService {
    static let bucket = "news"
    static let folder = "push"

    /// يضغط الصورة مثل صور الأخبار ويرفعها إلى `news/push/<uuid>.jpg` — يرجع المسار داخل المستودع، أو nil إن تعذّر
    static func upload(_ image: UIImage) async -> String? {
        guard let data = await Task.detached(priority: .userInitiated, operation: {
            ImageProcessor.process(image, for: .news)
        }).value else { return nil }
        let path = "\(folder)/\(UUID().uuidString.lowercased()).jpg"
        do {
            try await SupabaseConfig.client.storage
                .from(bucket)
                .upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: false))
            return path
        } catch {
            Log.error("[PUSH-IMAGE] خطأ رفع صورة الإشعار: \(error.localizedDescription)")
            return nil
        }
    }
}
