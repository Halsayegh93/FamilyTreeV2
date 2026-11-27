//
//  SignupPreview.swift
//  FamilyTreeV2
//
//  معاينة شاشات التسجيل الجديد بلا رمز دخول ولا سيرفر — للتصوير فقط (DEBUG):
//  `-uiPreviewSignup choose|complete` — «التسجيل» بالمربّعين (ومنه «من العائلة»/«من خارج العائلة»)، و«استكمال التسجيل».
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

    var body: some View {
        switch mode {
        case "complete":
            CompleteRegistrationPage(status: nil, onSent: {}, onLater: nil)
        default:
            SignupOriginFlow()
        }
    }
}
#endif
