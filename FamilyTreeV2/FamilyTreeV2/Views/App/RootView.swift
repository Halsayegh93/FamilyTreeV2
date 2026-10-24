import SwiftUI

struct RootView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @ObservedObject private var network = NetworkMonitor.shared

    var body: some View {
        Group {
            if let tmpPage = TMPAdminHarness.page { TMPAdminHarness(page: tmpPage) } else { // TMP-SHOT
            switch authVM.status {
            case .unauthenticated:
                LoginView()

            case .checking:
                SplashScreenView()

            case .authenticatedNoProfile:
                RegistrationView()

            case .pendingApproval:
                WaitingForApprovalView()

            case .accountFrozen:
                FrozenAccountView()

            case .deviceLimitExceeded:
                DeviceLimitView()
                    .environmentObject(appSettingsVM)

            case .deviceRevoked:
                DeviceRevokedView()
                    .environmentObject(notificationVM)
                    .environmentObject(appSettingsVM)

            case .deviceOverLimit:
                DeviceOverLimitView()
                    .environmentObject(notificationVM)
                    .environmentObject(appSettingsVM)

            case .fullyAuthenticated:
                // التحديث الإجباري — النسخة أقل من الحد الأدنى. المالك مستثنى حتى
                // لا يقفل نفسه خارج التطبيق لو رفع الحد قبل ما يحدّث جهازه.
                if AppBuild.current < (appSettingsVM.settings.iosMinBuild ?? 0)
                    && authVM.currentUser?.role != .owner {
                    ForceUpdateView()
                } else if appSettingsVM.settings.maintenanceMode && !authVM.canModerate {
                    MaintenanceModeView()
                } else {
                    MainTabView()
                }
            }
            } // TMP-SHOT
        }
        .animation(.default, value: authVM.status)
        // Alert مركزي لأي عملية كتابة بدون اتصال — ViewModels تستدعي
        // NetworkMonitor.shared.requireOnline() اللي يضبط هذا الفلاج.
        .dsAlert(
            L10n.t("لا يوجد اتصال بالإنترنت", "No Internet Connection"),
            isPresented: $network.showOfflineAlert
        ) {
            Button(L10n.t("حسناً", "OK")) {}
        } message: {
            Text(L10n.t(
                "لا يمكن تنفيذ هذا الإجراء بدون اتصال بالإنترنت. تأكّد من الاتصال ثم حاول مجدّداً.",
                "This action requires an internet connection. Please check your connection and try again."
            ))
        }
    }
}

// MARK: - Maintenance Mode View

struct MaintenanceModeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            Image(systemName: "wrench.and.screwdriver")
                .font(DS.Font.scaled(80, weight: .regular))
                .foregroundStyle(DS.Color.primary)

            Text(L10n.t("التطبيق تحت الصيانة", "App Under Maintenance"))
                .font(DS.Font.title1)
                .foregroundColor(DS.Color.textPrimary)
                .multilineTextAlignment(.center)

            Text(L10n.t(
                "نقوم حالياً بتحديث التطبيق. يرجى المحاولة لاحقاً.",
                "We're currently updating the app. Please try again later."
            ))
            .font(DS.Font.body)
            .foregroundColor(DS.Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Spacing.xxxl)

            Spacer()

            DSSecondaryButton(
                L10n.t("تحديث", "Refresh"),
                icon: "arrow.clockwise"
            ) {
                Task {
                    await appSettingsVM.fetchSettings()
                    await CategoryStore.shared.fetch()
                }
            }

            DSSecondaryButton(
                L10n.t("تسجيل الخروج", "Sign Out"),
                icon: "rectangle.portrait.and.arrow.right"
            ) {
                Task {
                    await authVM.signOut()
                }
            }
        }
        .padding(DS.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.background)
    }
}

// MARK: - Device Revoked View
struct DeviceRevokedView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var appSettingsVM: AppSettingsViewModel

    @State private var showDevicesSheet = false

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            VStack(spacing: DS.Spacing.xxl) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(DS.Color.warning.opacity(0.12))
                        .frame(width: 100, height: 100)
                    Image(systemName: "iphone.slash")
                        .font(DS.Font.scaled(42, weight: .bold))
                        .foregroundColor(DS.Color.warning)
                }

                VStack(spacing: DS.Spacing.md) {
                    Text(L10n.t("تم إزالة هذا الجهاز", "Device Removed"))
                        .font(DS.Font.title2)
                        .fontWeight(.black)
                        .foregroundColor(DS.Color.textPrimary)

                    Text(L10n.t(
                        "تم حذف هذا الجهاز من الأجهزة المرتبطة.\nيمكنك إدارة الأجهزة وإزالة جهاز آخر للمتابعة.",
                        "This device was removed from linked devices.\nManage your devices to continue."
                    ))
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.xxl)
                }

                Spacer()

                DSPrimaryButton(
                    L10n.t("إدارة الأجهزة", "Manage Devices"),
                    icon: "iphone.gen3"
                ) {
                    showDevicesSheet = true
                }
                .padding(.horizontal, DS.Spacing.lg)

                DSSecondaryButton(
                    L10n.t("تسجيل الخروج", "Sign Out"),
                    icon: "rectangle.portrait.and.arrow.right",
                    color: DS.Color.error
                ) {
                    Task { await authVM.signOut() }
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.bottom, DS.Spacing.xxxxl)
            }
        }
        .dsCenterBox(isPresented: $showDevicesSheet) {
            LinkedDevicesSheet()
                .environmentObject(appSettingsVM)
        }
        .task {
            await notificationVM.fetchLinkedDevices()
        }
    }
}


// MARK: - TMP-SHOT harness (temporary — reverted after screenshots)
struct TMPMemberBox: View { // TMP-SHOT
    let id: String
    @EnvironmentObject var memberVM: MemberViewModel
    @State private var show = true
    var body: some View {
        if let uuid = UUID(uuidString: id), let m = memberVM.member(byId: uuid) {
            Color.clear.dsCenterBox(isPresented: $show) { MemberDetailsView(member: m) }
        } else {
            Text("…")
        }
    }
}
struct TMPAdminHarness: View { // TMP-SHOT
    static let page: String? = {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-tmpAdmin"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }()
    static var didSetup = false
    static var tries = 0
    static let members: [FamilyMember] = {
        let json = ##"[{"id":"0efb9168-8434-41a8-96b7-6e7f2c7e10ab","full_name":"عبدالحميد اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"عبدالحميد","father_id":"6ea5f129-03c1-4171-8430-87d708f6cd9c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":0},{"id":"0f3cebc9-83bb-4043-92c5-118379c22f62","full_name":"محمد ناصر امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"محمد","father_id":"dd239d1a-ade8-4e98-9457-f727f79ae47a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":1},{"id":"20ce3e43-4b37-4d46-ba08-08fa6c45781c","full_name":"حسين علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"حسين","father_id":"c7e69d5f-4d1e-4e0a-855d-3023b2b5f633","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"1988-01-11","avatar_url":null,"is_married":true,"sort_order":2},{"id":"213e2a60-b59d-4939-8239-cee45ab2b3a2","full_name":"موسى محمدعلي حسن المحمدعلي","first_name":"موسى","father_id":"dd046d46-d2fc-464b-aee7-9bcf63534b27","role":"member","status":"active","gender":"male","is_deceased":true,"birth_date":"1860-01-01","avatar_url":null,"is_married":true,"sort_order":3},{"id":"21c5af3a-32a2-485a-a672-460beea6e410","full_name":"حمزة حسين علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"حمزة","father_id":"20ce3e43-4b37-4d46-ba08-08fa6c45781c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":4},{"id":"37c5930d-3050-4121-ae9d-ef21d6f45cd0","full_name":"مشعل عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"مشعل","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":5},{"id":"384c7928-c056-4c44-b81a-1aa37646ad20","full_name":"جعفر حسين علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"جعفر","father_id":"20ce3e43-4b37-4d46-ba08-08fa6c45781c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":6},{"id":"38d89dd8-5c94-4599-b9ef-ddd5b92af0f5","full_name":"حمد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"حمد","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"member","status":"active","gender":"male","is_deceased":true,"birth_date":"1958-01-01","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/38D89DD8-5C94-4599-B9EF-DDD5B92AF0F5.jpg","is_married":true,"sort_order":7},{"id":"3c4eb10f-d6f3-4b37-9753-7db60d1cb272","full_name":"حمد ناصر امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"حمد","father_id":"dd239d1a-ade8-4e98-9457-f727f79ae47a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":8},{"id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","full_name":"عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"عبدالحميد","father_id":"c669ee19-5956-4246-8505-321a8cfe40a0","role":"member","status":"active","gender":"male","is_deceased":true,"birth_date":"1920-01-01","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/4ED01112-8114-40F9-B1ED-DB02B5742CD7.jpg","is_married":true,"sort_order":9},{"id":"4f24cff6-1b20-48fe-8e86-415d73e2d061","full_name":"عبدالله اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"عبدالله","father_id":"6ea5f129-03c1-4171-8430-87d708f6cd9c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":10},{"id":"58413973-8eba-46ac-8d9c-664c3e2df6e0","full_name":"محمد حسين علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"محمد","father_id":"20ce3e43-4b37-4d46-ba08-08fa6c45781c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":11},{"id":"5e83cbe4-c973-4bf0-9fef-84b4f50f8d17","full_name":"احمد امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"احمد","father_id":"a38acd87-8513-4cf2-b458-205cddf0fa7a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":12},{"id":"665bdcc8-511a-4b7a-a221-a0f7b5ac339a","full_name":"انور امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"انور","father_id":"a38acd87-8513-4cf2-b458-205cddf0fa7a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"1984-03-07","avatar_url":null,"is_married":true,"sort_order":13},{"id":"6d9512c6-b91d-44ba-b70e-8fa063805bd4","full_name":"محمد علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"محمد","father_id":"c7e69d5f-4d1e-4e0a-855d-3023b2b5f633","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":14},{"id":"6ea5f129-03c1-4171-8430-87d708f6cd9c","full_name":"اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"اياد","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":15},{"id":"70c07109-7b72-4c5e-a7ed-346b70073388","full_name":"مهدي علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"مهدي","father_id":"c7e69d5f-4d1e-4e0a-855d-3023b2b5f633","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":16},{"id":"7cfb62dd-1d00-4e68-b7a3-be354fc11356","full_name":"احمد ناصر امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"احمد","father_id":"dd239d1a-ade8-4e98-9457-f727f79ae47a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":17},{"id":"84e78edc-703e-410d-8db9-fac7fc411a2b","full_name":"بدر امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"بدر","father_id":"a38acd87-8513-4cf2-b458-205cddf0fa7a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"1993-02-01","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/84E78EDC-703E-410D-8DB9-FAC7FC411A2B.jpg","is_married":true,"sort_order":18},{"id":"88d7b2f2-aca2-4705-952e-b863def266f8","full_name":"حسن صلاح عبدالحميد حسن موسى محمدعلي الصايغ","first_name":"حسن","father_id":"a1600043-00a7-4f44-bbe6-1f27bdd44736","role":"owner","status":"active","gender":"male","is_deceased":false,"birth_date":"1993-03-25","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/9849ab4f-fc16-495e-b82d-33811d4b8d3c.jpg","is_married":true,"sort_order":19},{"id":"95fe07ca-8380-47a1-8d1e-2236102e058e","full_name":"محمد صلاح عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"محمد","father_id":"a1600043-00a7-4f44-bbe6-1f27bdd44736","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"1989-04-23","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/95FE07CA-8380-47A1-8D1E-2236102E058E.jpg","is_married":true,"sort_order":20},{"id":"973a1ad3-5c1f-4805-8500-5f8c7642fbed","full_name":"يوسف انور امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"يوسف","father_id":"665bdcc8-511a-4b7a-a221-a0f7b5ac339a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"2016-07-03","avatar_url":null,"is_married":true,"sort_order":21},{"id":"a1600043-00a7-4f44-bbe6-1f27bdd44736","full_name":"صلاح عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"صلاح","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"admin","status":"active","gender":"male","is_deceased":false,"birth_date":"1963-05-20","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/A1600043-00A7-4F44-BBE6-1F27BDD44736.jpg","is_married":true,"sort_order":22},{"id":"a38acd87-8513-4cf2-b458-205cddf0fa7a","full_name":"امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"امير","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":23},{"id":"a66bb21a-ae97-4ccd-8758-e1987df64e77","full_name":"عبدالله صلاح عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"عبدالله","father_id":"a1600043-00a7-4f44-bbe6-1f27bdd44736","role":"admin","status":"active","gender":"male","is_deceased":false,"birth_date":"1998-07-10","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/A66BB21A-AE97-4CCD-8758-E1987DF64E77.jpg","is_married":true,"sort_order":24},{"id":"b527bb16-ebf1-4a18-b419-216e297ff2f7","full_name":"علي حسين علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"علي","father_id":"20ce3e43-4b37-4d46-ba08-08fa6c45781c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":25},{"id":"b875e856-13d0-40b5-9b3c-f047f3aaba6e","full_name":"حسن احمد امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"حسن","father_id":"5e83cbe4-c973-4bf0-9fef-84b4f50f8d17","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":26},{"id":"c1e9e8d0-b250-4a41-9381-a34298035c3f","full_name":"حمد اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"حمد","father_id":"6ea5f129-03c1-4171-8430-87d708f6cd9c","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"1995-11-08","avatar_url":null,"is_married":true,"sort_order":27},{"id":"c6275b2e-3429-4a96-9217-6669ea46bebb","full_name":"عبدالله احمد امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"عبدالله","father_id":"5e83cbe4-c973-4bf0-9fef-84b4f50f8d17","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":28},{"id":"c669ee19-5956-4246-8505-321a8cfe40a0","full_name":"حسن موسى محمدعلي حسن المحمدعلي","first_name":"حسن","father_id":"213e2a60-b59d-4939-8239-cee45ab2b3a2","role":"member","status":"active","gender":"male","is_deceased":true,"birth_date":"1897-01-01","avatar_url":"https://poxyxsgvzwmnmewytsiw.supabase.co/storage/v1/object/public/avatars/C669EE19-5956-4246-8505-321A8CFE40A0.jpg","is_married":true,"sort_order":29},{"id":"c7e69d5f-4d1e-4e0a-855d-3023b2b5f633","full_name":"علي عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"علي","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":30},{"id":"ce114642-b914-4846-aa98-46f6d3946bc1","full_name":"يوسف حمد اياد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"يوسف","father_id":"c1e9e8d0-b250-4a41-9381-a34298035c3f","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":"2025-05-05","avatar_url":null,"is_married":true,"sort_order":31},{"id":"d7242db4-a69e-473b-94a3-50afb15013df","full_name":"هاشم احمد امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"هاشم","father_id":"5e83cbe4-c973-4bf0-9fef-84b4f50f8d17","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":32},{"id":"dd046d46-d2fc-464b-aee7-9bcf63534b27","full_name":"محمدعلي حسن المحمدعلي","first_name":"محمدعلي","father_id":null,"role":"member","status":"active","gender":"male","is_deceased":true,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":33},{"id":"dd239d1a-ade8-4e98-9457-f727f79ae47a","full_name":"ناصر امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"ناصر","father_id":"a38acd87-8513-4cf2-b458-205cddf0fa7a","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":34},{"id":"e0490fa2-328a-4ba1-9e6a-eea6e85cde7f","full_name":"علي احمد امير عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"علي","father_id":"5e83cbe4-c973-4bf0-9fef-84b4f50f8d17","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":35},{"id":"7e57a000-0000-4000-8000-000000000007","full_name":"زيد عبدالحميد حسن موسى محمدعلي حسن المحمدعلي","first_name":"زيد","father_id":"4ed01112-8114-40f9-b1ed-db02b5742cd7","role":"member","status":"active","gender":"male","is_deceased":false,"birth_date":null,"avatar_url":null,"is_married":true,"sort_order":31}]"##
        return (try? JSONDecoder().decode([FamilyMember].self, from: Data(json.utf8))) ?? []
    }()
    static let notifs: [AppNotification] = {
        let json = ##"[]"##
        return (try? JSONDecoder().decode([AppNotification].self, from: Data(json.utf8))) ?? []
    }()
    static let news: [NewsPost] = {
        let json = ##"[{"id":"11111111-1111-4111-8111-111111111101","created_at":"2026-10-03T16:20:00+00:00","author_name":"إدارة العائلة","author_role":"admin","role_color":"#1F4E79","content":"مثال: مبروك المولود الجديد — جعله الله من الذرية الصالحة","type":"مولود","approval_status":"approved"},{"id":"11111111-1111-4111-8111-111111111102","created_at":"2026-10-01T09:00:00+00:00","author_name":"إدارة العائلة","author_role":"admin","role_color":"#1F4E79","content":"مثال: لقاء العائلة السنوي يوم الجمعة بعد صلاة العصر في ديوانية العائلة","type":"إعلان","approval_status":"approved"},{"id":"11111111-1111-4111-8111-111111111103","created_at":"2026-09-28T18:30:00+00:00","author_name":"إدارة العائلة","author_role":"admin","role_color":"#1F4E79","content":"مثال: ألف مبروك الزواج — بالرفاء والبنين","type":"زواج","approval_status":"approved"},{"id":"11111111-1111-4111-8111-111111111104","created_at":"2026-09-20T12:00:00+00:00","author_name":"إدارة العائلة","author_role":"admin","role_color":"#1F4E79","content":"مثال: ما رأيكم في موعد الرحلة العائلية؟","type":"تصويت","poll_question":"موعد الرحلة","poll_options":["الخميس","الجمعة","السبت"],"approval_status":"approved"},{"id":"11111111-1111-4111-8111-111111111105","created_at":"2026-09-10T08:00:00+00:00","author_name":"إدارة العائلة","author_role":"admin","role_color":"#1F4E79","content":"مثال: تم تحديث دليل استخدام التطبيق — راجعوا قسم الأسئلة الشائعة","type":"خبر","approval_status":"approved"}]"##
        return (try? JSONDecoder().decode([NewsPost].self, from: Data(json.utf8))) ?? []
    }()
    static let diws: [Diwaniya] = {
        let json = ##"[]"##
        return (try? JSONDecoder().decode([Diwaniya].self, from: Data(json.utf8))) ?? []
    }()
    static var owner: FamilyMember? {
        if ProcessInfo.processInfo.arguments.contains("-tmpAsParent") {
            return members.first { $0.role == .member && $0.firstName == "أحمد" }
        }
        if ProcessInfo.processInfo.arguments.contains("-tmpAsMember") {
            return members.first { $0.role == .member && $0.firstName == "حمد" }
        }
        return members.first { $0.role == .owner }
    }

    let page: String
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @EnvironmentObject var notificationVM: NotificationViewModel
    @EnvironmentObject var newsVM: NewsViewModel
    @State private var ready = false
    @State private var tab = 4
    @State private var showBox = true

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            if ready { content }
        }
        .onAppear {
            guard !Self.didSetup else { return }
            Self.didSetup = true
            authVM.currentUser = Self.owner
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: Notification.Name("tmpShotGo"), object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("tmpShotGo"))) { _ in
            if authVM.currentUser == nil, Self.tries < 5 {
                Self.tries += 1
                authVM.currentUser = Self.owner
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    NotificationCenter.default.post(name: Notification.Name("tmpShotGo"), object: nil)
                }
                return
            }
            restore()
            ready = true
            if page == "main" { // TMP-SHOT وضع العرض: البيانات التجريبية تبقى مهما تنقّل
                Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                    Task { @MainActor in
                        if memberVM.allMembers.count != Self.members.count
                            || newsVM.allNews.count != Self.news.count
                            || (DiwaniyasViewModel.tmpLast.map { $0.diwaniyas.count != Self.diws.count } ?? false) { restore() }
                    }
                }
            }
            for t in [1.0, 2.5, 4.0, 6.0, 9.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                    if memberVM.allMembers.count != Self.members.count
                        || (page == "notifs" && notificationVM.notifications.count != Self.notifs.count)
                        || ((page == "home" || page == "newscard") && newsVM.allNews.count != Self.news.count)
                        || (page == "diwaniyas" && (DiwaniyasViewModel.tmpLast?.diwaniyas.count ?? 0) != Self.diws.count) { restore() }
                }
            }
        }
    }

    private func restore() {
        memberVM.allMembers = Self.members
        memberVM.membersVersion += 1
        let all = page == "main"
        if all || page == "notifs" || (page == "home" || page == "newscard") { notificationVM.notifications = Self.notifs }
        if all || (page == "home" || page == "newscard") { newsVM.allNews = Self.news }
        if all || page == "diwaniyas" { DiwaniyasViewModel.tmpLast?.diwaniyas = Self.diws }
    }

    @ViewBuilder private var content: some View {
        switch page {
        case "guide":
            Color.clear.dsCenterBox(isPresented: $showBox) { AppGuideBox().environmentObject(authVM) }
        case "dashboard": AdminDashboardView(selectedTab: $tab)
        case "tree": TreeTabContainer(selectedTab: $tab)
        case "notifs": NavigationStack { NotificationsCenterView() }
        case "main": MainTabView()
        case "home": HomeNewsView(selectedTab: $tab)
        case "member": TMPMemberBox(id: ProcessInfo.processInfo.arguments.drop(while: { $0 != "-tmpMember" }).dropFirst().first ?? "")
        case "newscard": ScrollView { HomeNewsPreviewCard(onTap: {}).padding(.horizontal, DS.Spacing.lg).padding(.top, 64) }
        case "diwaniyas": DiwaniyasView(selectedTab: $tab)
        case "profile": ProfileView(selectedTab: $tab)
        case "requests": NavigationStack { AdminAllRequestsView() }
        case "inbox": NavigationStack { AdminInboxView() }
        case "activity": NavigationStack { AdminActivityLogView() }
        case "members": NavigationStack { AdminMembersDirectoryView() }
        case "team": NavigationStack { AdminModeratorsView() }
        case "health": NavigationStack { AdminTreeHealthView() }
        case "bans": NavigationStack { AdminBannedPhonesView() }
        case "categories": NavigationStack { CategoriesManagerView() }
        case "projects": NavigationStack { FamilyProjectsView() }
        case "archive": NavigationStack { FamilyArchiveView() }
        case "login": LoginView()
        case "waiting": WaitingForApprovalView()
        case "frozen": FrozenAccountView()
        case "devices": DeviceLimitView()
        case "deaths": NavigationStack { DeathAnnouncementsPage() }
        case "addproj": DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { AddProjectView(showAddedAlert: .constant(false)) }
        case "addarch": DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { ArchiveUploadSheet(archiveVM: FamilyArchiveViewModel(), defaultCategory: .documents) }
        case "contactbox": DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { MemberContactFormView() }
        case "death": DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { DeathAnnouncementBox(target: DeathAnnouncementTarget(id: UUID(), name: "حمد صالح محمد المحمدعلي", isFemale: false), onClose: {}) }
        case "deathf": DSCenterPanel(onBackgroundTap: nil, hugsContent: true) { DeathAnnouncementBox(target: DeathAnnouncementTarget(id: UUID(), name: "فاطمة صالح محمد المحمدعلي", isFemale: true), onClose: {}) }
        default: Text(page)
        }
    }
}

