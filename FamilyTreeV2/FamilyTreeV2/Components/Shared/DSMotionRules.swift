import Foundation
import CoreGraphics

// MARK: - قواعد الحركة الخالصة (الوحدة A1، «انميشن بالتحديثات الجديدة» — المالك ٢٠٢٦-١١-٢٧)
//
// ما تقرّره الحركة بلا SwiftUI، فيُفحص بلا محاكي (`tests/admin-redesign/A1/main.swift`):
//  • الأزمنة الجديدة مرة واحدة هنا، و`DSMotion` (DSComposer.swift) يبني منها حركاته — الخروج أسرع من الدخول (≈ ٦٠٪).
//  • اتجاه الانتقال بين مربّعات التسجيل: التالي يدخل من جهة نهاية السطر ويخرج القديم نحو بدايته، والرجوع بالعكس —
//    في العربية النهاية يسار الشاشة، فالإزاحة الفعلية (x) تنعكس.
//  • «تقليل الحركة»: لا انزلاق ولا تكبير ولا رسم — تلاشٍ فقط، أو ثابت.

enum DSMotionRules {

    // MARK: الأزمنة (ثوانٍ)

    enum Timing {
        /// دخول مربّع التسجيل التالي (انزلاق قصير + تلاشٍ)
        static let stepIn: Double = 0.34
        /// خروج المربّع السابق — أسرع من الدخول
        static let stepOut: Double = DSMotionRules.exitDuration(enter: stepIn)
        /// انكشاف حقل داخل المربّع نفسه («نعم» ← «اسم الوالدة الرباعي»)
        static let revealIn: Double = 0.3
        static let revealOut: Double = DSMotionRules.exitDuration(enter: revealIn)
        /// الحلقة الذهبية حول صورة العضو ترسم نفسها مرة (بعد قفزة الصورة)
        static let ringDraw: Double = 0.6
        static let ringDelay: Double = 0.18
        /// الزخرفة تحت الاسم تمتدّ من المعيّن إلى الطرفين (بعد الاسم)
        static let ornamentDraw: Double = 0.45
        static let ornamentDelay: Double = 0.24
        /// كم يبقى المربّع المختار ظاهراً بقفزته قبل الانتقال (ليرى العضو اختياره)
        static let selectHold: Double = 0.16
        /// صعود القفزة قبل أن تستقرّ بنابض
        static let popUp: Double = 0.1
        /// مهلة بعد آخر حرف قبل إظهار خطأ الحقل تحته (الفحص بعد انتهاء الكتابة، لا مع كل حرف)
        static let settle: Double = 1.2
        /// حبّة سطر التحية في «اليوم» تظهر بعد العنوان
        static let pillDelay: Double = 0.13
        static let pillIn: Double = 0.28
    }

    /// نسبة الخروج إلى الدخول (Material/HIG: ٦٠–٧٠٪ — الخروج ردّ لا عرض)
    static let exitRatio: Double = 0.6

    static func exitDuration(enter: Double) -> Double {
        (enter * exitRatio * 1000).rounded() / 1000
    }

    // MARK: المسافات

    /// انزلاق المربّع بين الخطوتين — قصير: إحساس بالاتجاه لا رحلة
    static let stepShift: CGFloat = 28
    /// القفزة حين يُختار مربّع كبير (أكبر قليلاً ثم يستقرّ)
    static let selectPopScale: CGFloat = 1.06
    /// خانات «طلب تعديل» تقفز من هذا المقاس
    static let tilePopScale: CGFloat = 0.9

    // MARK: «تقليل الحركة»

    enum Style: Equatable {
        /// الحركة كاملة (انزلاق/تكبير/رسم)
        case full
        /// تلاشٍ فقط
        case fade
    }

    static func style(reduceMotion: Bool) -> Style { reduceMotion ? .fade : .full }

    /// قفزة الاختيار ومهلتها: بلا قفزة ولا انتظار مع «تقليل الحركة» (التحديد يظهر بالإطار فقط)
    static func selectHold(reduceMotion: Bool) -> Double { reduceMotion ? 0 : Timing.selectHold }

    /// الرسم (الحلقة/الزخرفة) يبدأ من هذا التقدّم: صفر يرسم، وواحد = مرسوم كاملاً بلا حركة
    static func drawStart(reduceMotion: Bool) -> CGFloat { reduceMotion ? 1 : 0 }

    // MARK: اتجاه الخطوات

    /// إلى الأمام إن كانت الخطوة الجديدة بعد القديمة
    static func isForward(from: Int, to: Int) -> Bool { to >= from }

    /// إزاحة x الفعلية على الشاشة (موجب = يمين) لدخول المربّع الجديد وخروج القديم.
    /// LTR: التالي يدخل من اليمين ويخرج القديم يساراً · RTL: بالعكس · الرجوع: عكس التقدّم.
    /// «تقليل الحركة»: صفر (تلاشٍ فقط).
    static func stepOffsets(forward: Bool, rtl: Bool, reduceMotion: Bool,
                            distance: CGFloat = stepShift) -> (insert: CGFloat, remove: CGFloat) {
        guard !reduceMotion else { return (0, 0) }
        let toEnd: CGFloat = rtl ? -1 : 1          // اتجاه «نهاية السطر» على الشاشة
        let sign: CGFloat = forward ? 1 : -1
        return (insert: distance * toEnd * sign, remove: -distance * toEnd * sign)
    }

    // MARK: نقاط الخطوات

    /// خطوات التسجيل الثلاث: الصلة بالعائلة · البيانات · المراجعة
    enum SignupStep: Int, CaseIterable { case choose = 0, form = 1, review = 2 }

    static let signupStepCount = SignupStep.allCases.count
}
