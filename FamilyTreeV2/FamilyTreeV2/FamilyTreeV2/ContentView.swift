//
//  ContentView.swift
//  FamilyTreeV2
//
//  Created by HASAN on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        #if DEBUG
        // معاينة «المرسل» و«تمت معالجتها» بلا سيرفر (`-uiPreviewRequestTrail <mode>`) — للتصوير فقط
        if let mode = JoinCardPreview.mode {
            // بطاقة «طلب انضمام» (العيّنة ١٨): `-uiPreviewJoinCard match|nomatch|female|box`
            JoinCardPreviewScreen(mode: mode)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        } else if let mode = SignupPreview.mode {
            // شاشات التسجيل الجديد للتصوير: `-uiPreviewSignup choose|complete`
            SignupPreviewScreen(mode: mode)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        } else if let mode = AdminTrailPreview.mode {
            AdminTrailPreviewScreen(mode: mode)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar"))
        } else {
            root
        }
        #else
        root
        #endif
    }

    private var root: some View {
        // بلا اتصال: شاشة البداية فوق كل شيء (`OfflineHold`) بدل شريطي الاتصال
        NavigationStack {
            RootView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
