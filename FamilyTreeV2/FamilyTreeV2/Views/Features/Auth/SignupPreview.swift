//
//  SignupPreview.swift
//  FamilyTreeV2
//
//  معاينة شاشات التسجيل الجديد بلا رمز دخول ولا سيرفر — للتصوير فقط (DEBUG):
//  `-uiPreviewSignup choose|complete|family[-f]|spouse[-f]|sent[-f]|admin-spouse[-found]|maintenance|maintenance-msg` (الأخير بسبب صيانة عيّنة) — «التسجيل» بالمربّعين (ومنه «من العائلة»/«من خارج العائلة»)، و«استكمال التسجيل».
//  لا شيء يُرسل: لا حساب في هذه المعاينة، وأزرار الإرسال لا تجد جلسة.
//

#if DEBUG
import SwiftUI

enum SignupPreview {
    static var mode: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiPreviewSignup"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct SignupPreviewScreen: View {
    let mode: String
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        switch mode {
        case "maintenance":
            MaintenanceModeView()
        case "maintenance-msg":
            MaintenanceModeView()
                .onAppear {
                    appSettingsVM.settings.maintenanceMessage =
                        "نحدّث بيانات الشجرة وصور الأعضاء، ونعود خلال ساعات قليلة إن شاء الله."
                }
        case "complete":
            CompleteRegistrationPage(status: nil, onSent: {}, onLater: nil)
        // «هل أحد أفراد أسرتك من العائلة؟» وبيانات الزوجة/الزوج و«تم إرسال البيانات» (العيّنة spouse2)؛ -f = حساب امرأة
        case "family", "family-f":
            CompleteRegistrationPage(preview: .family, gender: mode.hasSuffix("-f") ? "female" : "male")
        case "spouse", "spouse-f":
            CompleteRegistrationPage(preview: .spouse, gender: mode.hasSuffix("-f") ? "female" : "male")
        case "sent", "sent-f":
            let female = mode.hasSuffix("-f")
            CompleteRegistrationPage(preview: .spouse, gender: female ? "female" : "male",
                                     sent: .init(relation: female ? .husband : .wife,
                                                 typedName: female ? "زيد حسن علي أحمد" : "فاطمة أحمد زيد حسن"))
        // بطاقة «الوارد» لطلب ربط الزوج (بيانات معاينة، بلا سيرفر)
        case "admin-spouse", "admin-spouse-found":
            OutsideSpouseRequestPreview(found: mode == "admin-spouse-found")
        // «الأسرة» عند الزوجة صاحبة الحساب وزوجها من خارج العائلة: خانة الزوج ثم المفتاحان (المكوّن الحقيقي `.own`، بلا حفظ)
        case "profile-spouse":
            ScrollView {
                DSFormCard(L10n.t("الأسرة", "My Family"), icon: "person.2.fill", color: DS.Color.textSecondary) {
                    VStack(spacing: DS.Spacing.sm) {
                        DSRow(icon: "person.fill", tint: DS.Color.male, title: "محمد حسن حسين الكندري",
                              subtitle: L10n.t("الزوج · من خارج العائلة", "Husband · outside the family")) { EmptyView() }
                            .profileCell()
                        WomanVisibilityAdminSection(womanId: UUID(), mode: .own)
                    }
                }
                .dsPageMargin()
                .padding(.top, DS.Spacing.xxl)
            }
            .background(DS.Color.background.ignoresSafeArea())
        default:
            SignupOriginFlow()
        }
    }
}
#endif
