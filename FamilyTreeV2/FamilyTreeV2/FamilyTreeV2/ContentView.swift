//
//  ContentView.swift
//  FamilyTreeV2
//
//  Created by HASAN on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        // Each main tab owns its NavigationStack. An outer stack can capture a
        // tab's destination and push it outside TabView, losing its route scope.
        // Auth screens switch through RootView and present their own sheets.
        RootView()
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
