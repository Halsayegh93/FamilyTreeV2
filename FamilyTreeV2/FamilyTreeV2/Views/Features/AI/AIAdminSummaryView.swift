import SwiftUI

struct AIAdminSummaryView: View {
    @StateObject private var aiVM: AIViewModel
    @Environment(\.dismiss) var dismiss

    init(userId: String) {
        _aiVM = StateObject(wrappedValue: AIViewModel(userId: userId))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.background.ignoresSafeArea()


                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.xl) {
                        // Header gradient card
                        DSGradientCard(gradient: DS.Color.gradientPrimary) {
                            HStack(spacing: DS.Spacing.md) {
                                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                                    Text(L10n.t("التحليل الذكي", "AI Analysis"))
                                        .font(DS.Font.title2)
                                        .foregroundColor(DS.Color.textOnPrimary)
                                    Text(L10n.t("ملخص إداري مدعوم بالذكاء الاصطناعي", "AI-powered admin summary"))
                                        .font(DS.Font.subheadline)
                                        .foregroundColor(DS.Color.overlayText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                ZStack {
                                    Circle()
                                        .fill(DS.Color.overlayIcon)
                                        .frame(width: 50, height: 50)
                                    Image(systemName: "sparkles")
                                        .font(DS.Font.scaled(22, weight: .bold))
                                        .foregroundColor(DS.Color.textOnPrimary)
                                }
                            }
                            .padding(DS.Spacing.xl)
                        }

                        // Stats cards
                        if let stats = aiVM.adminStats {
                            statsGrid(stats)
                        }

                        // Admin Summary
                        if !aiVM.adminSummary.isEmpty {
                            summaryCard
                        }

                        // Tree Analysis
                        if !aiVM.treeAnalysis.isEmpty {
                            treeAnalysisCard
                        }

                        // Error
                        if let error = aiVM.adminError ?? aiVM.treeAnalysisError {
                            errorCard(error)
                        }

                        // Loading
                        if aiVM.isAdminLoading || aiVM.isTreeAnalysisLoading {
                            loadingCard
                        }

                        // Empty state — no data and not loading
                        if !aiVM.isAdminLoading && !aiVM.isTreeAnalysisLoading
                            && aiVM.adminSummary.isEmpty && aiVM.treeAnalysis.isEmpty
                            && aiVM.adminStats == nil
                            && aiVM.adminError == nil && aiVM.treeAnalysisError == nil {
                            VStack(spacing: DS.Spacing.lg) {
                                Image(systemName: "sparkles")
                                    .font(DS.Font.scaled(40))
                                    .foregroundColor(DS.Color.textTertiary)
                                Text(L10n.t("لا تتوفر بيانات للتحليل حالياً", "No data available for analysis"))
                                    .font(DS.Font.title3)
                                    .foregroundColor(DS.Color.textSecondary)
                                DSSecondaryButton(L10n.t("إعادة المحاولة", "Retry"), icon: "arrow.clockwise") {
                                    Task {
                                        await aiVM.fetchAdminSummary()
                                        await aiVM.analyzeTree()
                                    }
                                }
                                .frame(width: 200)
                            }
                            .padding(.top, DS.Spacing.xxxl)
                        }
                    }
                    .padding(DS.Spacing.lg)
                }
            }
            .navigationTitle(L10n.t("التحليل الذكي", "AI Analysis"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                        .font(DS.Font.calloutBold)
                        .foregroundColor(DS.Color.primary)
                }
            }
            .task {
                await aiVM.fetchAdminSummary()
                await aiVM.analyzeTree()
            }
        }
        .environment(\.layoutDirection, LanguageManager.shared.layoutDirection)
    }

    // MARK: - Stats Grid

    private func statsGrid(_ stats: AIAdminResponse.AdminStats) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: DS.Spacing.md) {
            DSStatCard(
                title: L10n.t("إجمالي", "Total"),
                value: "\(stats.total_members ?? 0)",
                icon: "person.3.fill",
                color: DS.Color.primary
            )
            DSStatCard(
                title: L10n.t("نشط", "Active"),
                value: "\(stats.active ?? 0)",
                icon: "checkmark.circle.fill",
                color: DS.Color.success
            )
            DSStatCard(
                title: L10n.t("معلق", "Pending"),
                value: "\(stats.pending_requests ?? 0)",
                icon: "clock.fill",
                color: DS.Color.warning
            )
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(
                title: L10n.t("ملخص الإدارة", "Admin Summary"),
                icon: "sparkles"
            )

            DSCard {
                Text(aiVM.adminSummary)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .padding(DS.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Refresh button
            DSSecondaryButton(
                L10n.t("تحديث الملخص", "Refresh Summary"),
                icon: "arrow.clockwise"
            ) {
                Task { await aiVM.fetchAdminSummary() }
            }
            .padding(.horizontal, DS.Spacing.lg)
        }
    }

    // MARK: - Tree Analysis Card

    private var treeAnalysisCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            DSSectionHeader(
                title: L10n.t("تحليل الشجرة", "Tree Analysis"),
                icon: "chart.bar.fill"
            )

            DSCard {
                Text(aiVM.treeAnalysis)
                    .font(DS.Font.body)
                    .foregroundColor(DS.Color.textPrimary)
                    .padding(DS.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Error Card

    private func errorCard(_ error: String) -> some View {
        DSCard {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(DS.Color.error)
                Text(error)
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.error)
            }
            .padding(DS.Spacing.lg)
        }
    }

    // MARK: - Loading Card

    private var loadingCard: some View {
        DSCard {
            HStack(spacing: DS.Spacing.md) {
                ProgressView()
                    .tint(DS.Color.primary)
                Text(L10n.t("جاري التحليل...", "Analyzing..."))
                    .font(DS.Font.callout)
                    .foregroundColor(DS.Color.textSecondary)
            }
            .padding(DS.Spacing.lg)
            .frame(maxWidth: .infinity)
        }
    }
}
