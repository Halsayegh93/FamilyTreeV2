import Foundation
import SwiftUI
import Combine
import Supabase

/// ViewModels belong to one authenticated session, never to the lifetime of the app.
@MainActor
class AppState: ObservableObject {
    let authVM: AuthViewModel
    @Published private(set) var memberVM: MemberViewModel
    @Published private(set) var newsVM: NewsViewModel
    @Published private(set) var notificationVM: NotificationViewModel
    @Published private(set) var adminRequestVM: AdminRequestViewModel
    @Published private(set) var projectsVM: ProjectsViewModel
    @Published private(set) var appSettingsVM: AppSettingsViewModel
    @Published private(set) var sessionRevision = UUID()
    private var activeProfileId: UUID?
    private var loadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        authVM = AuthViewModel()
        memberVM = MemberViewModel()
        newsVM = NewsViewModel()
        notificationVM = NotificationViewModel()
        adminRequestVM = AdminRequestViewModel()
        projectsVM = ProjectsViewModel()
        appSettingsVM = AppSettingsViewModel()
        wireDependencies()
        authVM.$status.combineLatest(authVM.$currentUser.map { $0?.id })
            .sink { [weak self] status, profileId in self?.updateSession(status: status, profileId: profileId) }
            .store(in: &cancellables)
    }

    private func wireDependencies() {
        authVM.notificationVM = notificationVM
        authVM.appSettingsVM = appSettingsVM
        appSettingsVM.authVM = authVM
        notificationVM.configure(authVM: authVM)
        notificationVM.appSettingsVM = appSettingsVM
        memberVM.configure(authVM: authVM, notificationVM: notificationVM)
        newsVM.configure(authVM: authVM, memberVM: memberVM, notificationVM: notificationVM)
        adminRequestVM.configure(authVM: authVM, memberVM: memberVM, notificationVM: notificationVM, newsVM: newsVM)
        projectsVM.configure(authVM: authVM, notificationVM: notificationVM)
        let realtime = RealtimeManager.shared
        realtime.memberVM = memberVM
        realtime.newsVM = newsVM
        realtime.notificationVM = notificationVM
        realtime.projectsVM = projectsVM
    }

    private func replaceSessionModels() {
        memberVM = MemberViewModel()
        newsVM = NewsViewModel()
        notificationVM = NotificationViewModel()
        adminRequestVM = AdminRequestViewModel()
        projectsVM = ProjectsViewModel()
        appSettingsVM = AppSettingsViewModel()
        wireDependencies()
        sessionRevision = UUID()
    }

    private func updateSession(status: AuthViewModel.AuthStatus, profileId: UUID?) {
        guard status == .fullyAuthenticated, let profileId,
              let accountId = authVM.supabase.auth.currentUser?.id else {
            if activeProfileId != nil || status == .unauthenticated || status == .accountFrozen {
                loadTask?.cancel()
                loadTask = nil
                activeProfileId = nil
                RealtimeManager.shared.unsubscribe()
                CacheManager.shared.clearAll()
                SharedSessionStore.clear()
                replaceSessionModels()
            }
            return
        }
        guard activeProfileId != profileId else { return }
        loadTask?.cancel()
        RealtimeManager.shared.unsubscribe()
        if activeProfileId != nil { CacheManager.shared.clearAll() }
        CacheManager.shared.beginAccount(accountId)
        activeProfileId = profileId
        replaceSessionModels()
        let revision = sessionRevision
        // Capture this bundle; a suspended task must never operate on a newer one.
        let member = memberVM, news = newsVM, notifications = notificationVM, projects = projectsVM
        loadTask = Task { @MainActor [weak self] in
            async let m: () = member.fetchAllMembers(force: true)
            async let n: () = news.fetchNews(force: true)
            async let notif: () = notifications.fetchNotifications(force: true)
            async let proj: () = projects.fetchProjects()
            _ = await (m,n,notif,proj)
            guard !Task.isCancelled, let self, self.sessionRevision == revision,
                  self.activeProfileId == profileId, self.authVM.status == .fullyAuthenticated else { return }
            RealtimeManager.shared.subscribe()
            await notifications.registerDevice()
            guard !Task.isCancelled, self.sessionRevision == revision else { return }
            await notifications.reRegisterPushTokenIfNeeded()
        }
    }
}
