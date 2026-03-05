//
//  FamilyTreeV2App.swift
//  FamilyTreeV2
//
//  Created by HASAN on 13/02/2026.
//

import SwiftUI
import UserNotifications

@main
struct FamilyTreeV2App: App {
    @UIApplicationDelegateAdaptor(PushNotificationDelegate.self) var pushDelegate
    @StateObject private var appState = AppState()
    @ObservedObject private var langManager = LanguageManager.shared
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState.authVM)
                .environmentObject(appState.memberVM)
                .environmentObject(appState.newsVM)
                .environmentObject(appState.notificationVM)
                .environmentObject(appState.adminRequestVM)
                .environment(\.locale, langManager.locale)
                .environment(\.layoutDirection, langManager.layoutDirection)
                .environment(\.multilineTextAlignment, langManager.selectedLanguage == "ar" ? .leading : .trailing)
                .offset(x: langManager.selectedLanguage == "ar" ? 1 : -1, y: 0)
                .preferredColorScheme(preferredScheme)
                .id(langManager.selectedLanguage)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceiveAPNSToken)) { note in
                    guard let token = note.object as? String else { return }
                    Task { await self.appState.notificationVM.registerPushToken(token) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didReceivePushNotification)) { _ in
                    Task { await self.appState.notificationVM.fetchNotifications() }
                }
                .onReceive(NotificationCenter.default.publisher(for: .didTapPushNotification)) { _ in
                    Task { await self.appState.notificationVM.fetchNotifications() }
                }
        }
    }
}
