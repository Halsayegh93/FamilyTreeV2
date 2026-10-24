import SwiftUI

/// بوستات المناسبات — للإدارة والمشرفين (canModerate).
/// أول شاشة: أنواع البوستات فقط (مربع لكل نوع). الضغط على نوع يفتح شاشته (OccasionPostEditorView)
/// بحقوله هو فقط. نوع ثاني يبدأ من جديد، والرجوع لنفس النوع يحتفظ باللي تعبّى.
struct OccasionComposerView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var memberVM: MemberViewModel
    @StateObject private var vm: OccasionComposerViewModel
    @StateObject private var diwaniyasVM = DiwaniyasViewModel()
    @StateObject private var familyNamesVM = FamilyNamesViewModel()
    @State private var showEditor = false

    /// vm قابل للتمرير (للمعاينة)؛ الافتراضي حالة جديدة
    init(vm: OccasionComposerViewModel? = nil) {
        _vm = StateObject(wrappedValue: vm ?? OccasionComposerViewModel())
    }

    var body: some View {
        Group {
            if authVM.canModerate {
                typeList
            } else {
                DSEmptyView(L10n.t("هذي الصفحة للإدارة والمشرفين", "Admins and moderators only"),
                            icon: "lock.fill")
            }
        }
        .navigationTitle(L10n.t("الإعلانات والمناسبات", "Announcements & occasions"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showEditor) {
            OccasionPostEditorView(vm: vm)
        }
        .task { await loadData() }
        .onChange(of: memberVM.membersVersion) { _ in
            vm.updateFamily(memberVM.allMembers)
        }
    }

    /// أعضاء الشجرة + الديوانيات + أسماء العوائل (للاختيارات) + خط التصميم مبكراً
    private func loadData() async {
        vm.updateFamily(memberVM.allMembers)
        if memberVM.allMembers.isEmpty {
            await memberVM.fetchAllMembers()
            vm.updateFamily(memberVM.allMembers)
        }
        await diwaniyasVM.fetchDiwaniyas()
        vm.updateDiwaniyas(diwaniyasVM.diwaniyas)
        await familyNamesVM.fetch()
        vm.updateFamilyNames(familyNamesVM.activeNames)
        await vm.kit.prepare([])
    }

    // MARK: أنواع البوستات

    private var typeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text(L10n.t("الخطوة ١ من ٤", "Step 1 of 4"))
                        .dsFont(.caption)
                        .foregroundColor(DS.Color.textSecondary)
                    Text(L10n.t("ماذا تريد أن تنشئ؟", "What would you like to create?"))
                        .dsFont(.headline)
                        .foregroundColor(DS.Color.textPrimary)
                    Text(L10n.t("اختر النوع، أضف التفاصيل، ثم عاين واحفظ أو شارك.",
                                "Choose a type, add the details, then preview and save or share."))
                        .dsFont(.subtitle)
                        .foregroundColor(DS.Color.textSecondary)
                }
                VStack(spacing: DS.Spacing.sm) {
                    ForEach(vm.templates) { t in
                        Button {
                            vm.open(t)
                            showEditor = true
                        } label: {
                            OccasionTypeTile(template: t)
                        }
                        .buttonStyle(DSScaleButtonStyle())
                        .accessibilityHint(t.subtitle)
                    }
                }
                if authVM.isAdmin {
                    DisclosureGroup(L10n.t("روابط الإعلانات", "Announcement links")) {
                        OccasionLinksSection()
                            .padding(.top, DS.Spacing.sm)
                    }
                    .dsFont(.subtitle)
                }
            }
            .padding(DS.Spacing.lg)
        }
        .background(DS.Color.background.ignoresSafeArea())
    }
}

/// مربع نوع البوست: أيقونة بلون تصميمه + الاسم + وصف قصير
private struct OccasionTypeTile: View {
    let template: OccasionTemplate

    var body: some View {
        let style = template.tileStyle
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: template.icon)
                .font(DS.Font.scaled(22, weight: .semibold))
                .foregroundColor(style.symbol)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(style.fill))
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(template.tileTitle)
                    .dsFont(.rowTitle)
                    .foregroundColor(DS.Color.textPrimary)
                Text(template.subtitle)
                    .dsFont(.caption)
                    .foregroundColor(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DSChevron()
        }
        .padding(DS.Spacing.md)
        .dsCard(padding: nil)
        .contentShape(Rectangle())
    }
}
