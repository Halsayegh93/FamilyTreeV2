//
//  ContentView.swift
//  FamilyTreeV2
//
//  Created by HASAN on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
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
