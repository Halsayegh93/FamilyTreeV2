//
//  ContentView.swift
//  FamilyTreeV2
//
//  Created by HASAN on 13/02/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            RootView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthViewModel())
}
