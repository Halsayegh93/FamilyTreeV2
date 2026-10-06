import SwiftUI

// MARK: - رسومات العائلة المتحرّكة
//
// المشاهد الكبيرة في FTTileScenes.swift (مربّعات الرئيسية والصفحات الفاضية) وFTPlaceScenes.swift
// (بطاقة الترحيب، تحميل الشجرة، الانتظار، الإشعارات الفاضية، الدخول). هنا الأغلفة الصغيرة المشتركة.
// «تقليل الحركة»: الرسم ثابت كما هو بلا أي حركة.

/// ساعة حركة مشتركة — TimelineView متوقّف عند «تقليل الحركة» (الوقت = ٠ فيبقى الرسم ثابتاً).
private struct ArtClock<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            content(reduceMotion ? 0 : max(0, tl.date.timeIntervalSince(start)))
        }
        .onAppear { start = Date() }
    }
}

// MARK: - الصفحات الفاضية

/// رسمة الحالة الفارغة — لوحة واحدة هادئة (طلب المالك ٢٠٢٦-١٠-٠٥ «أبسط وأقوى وباعتدال»): شعار القسم
/// المصمت (الدلّة، الدكان، الكتاب…) أو رمز الصفحة داخل قرص بلون القسم، يتنفّس ببطء. `FTEmptyScenes`
/// (Components/Shared/FTTileScenes.swift).
struct EmptyStateArt: View {
    let icon: String
    let tint: Color
    /// مشهد القسم بدل الأيقونة (الديوانيات تُعرف من رمزها تلقائياً)
    var kind: FTTileScenes.Kind? = nil

    private var special: FTTileScenes.Kind? {
        if let kind { return kind }
        if icon.contains("mappin") || icon.contains("map") || icon.contains("tent") || icon.contains("cup") { return .diwaniya }
        return nil
    }

    private var placeName: String? {
        switch special {
        case .tree?: return "tree"
        case .diwaniya?: return "diwaniya"
        case .library?: return "library"
        case .projects?: return "projects"
        case .contact?: return "contact"
        case nil: return nil
        }
    }

    var body: some View {
        // TMP-ART-TRIAL: رسم الاتجاه المختار، وإلا الحالي
        TrialArt(make: { ArtDispatch.empty($0, place: placeName, icon: icon, tint: tint) }) {
            FTEmptySceneView(kind: special, tint: tint, icon: special == nil ? icon : nil)
        }
            .frame(width: 130, height: 130)
            .accessibilityHidden(true)
    }
}

// MARK: - أيقونة الحالة الصغيرة (صفحات الإدارة والإشعارات)

/// أيقونة دائرة صغيرة تتنفّس ببطء (٨ ث، نفس إيقاع بقية الرسوم) — بلا حلقة نابضة ولا أرجحة. لـ `SysStateCard`.
struct FloatingIconArt: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 52

    var body: some View {
        TrialArt(make: { ArtDispatch.stateIcon($0, icon: icon, tint: tint, size: size) }) {   // TMP-ART-TRIAL
            emblem
        }
        .frame(width: size, height: size)
    }

    private var emblem: some View {
        ArtClock { t in
            ZStack {
                Circle().fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: size, height: size)
            .scaleEffect(1 + 0.025 * CGFloat(FTKit.breath(t)))
        }
        .accessibilityHidden(true)
    }
}
