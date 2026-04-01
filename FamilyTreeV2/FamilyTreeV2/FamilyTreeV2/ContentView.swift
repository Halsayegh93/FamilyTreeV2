//
//  ContentView.swift
//  FamilyTreeV2
//
//  Created by HASAN on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .top) {
            NavigationStack {
                RootView()
            }

            OfflineBanner()
                .padding(.top, DS.Spacing.xxxxl + DS.Spacing.lg)
                .animation(DS.Anim.snappy, value: NetworkMonitor.shared.isConnected)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
