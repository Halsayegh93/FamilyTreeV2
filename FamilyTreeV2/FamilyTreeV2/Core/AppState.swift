import Foundation
import SwiftUI
import Combine

// MARK: - AppState
// Central coordinator that owns all ViewModels and wires their dependencies.
// Injected at app root as @StateObject; individual VMs are injected as @EnvironmentObject.

@MainActor
class AppState: ObservableObject {
    let authVM: AuthViewModel
    let memberVM: MemberViewModel
    let newsVM: NewsViewModel
    let notificationVM: NotificationViewModel
    let adminRequestVM: AdminRequestViewModel
    
    init() {
        // 1. Create all VMs independently
        let auth = AuthViewModel()
        let member = MemberViewModel()
        let news = NewsViewModel()
        let notification = NotificationViewModel()
        let admin = AdminRequestViewModel()
        
        // 2. Wire dependencies after creation (avoids circular init)
        auth.notificationVM = notification
        notification.configure(authVM: auth)
        member.configure(authVM: auth, notificationVM: notification)
        news.configure(authVM: auth, memberVM: member, notificationVM: notification)
        admin.configure(authVM: auth, memberVM: member, notificationVM: notification, newsVM: news)
        
        // 3. Store references
        self.authVM = auth
        self.memberVM = member
        self.newsVM = news
        self.notificationVM = notification
        self.adminRequestVM = admin
    }
}
