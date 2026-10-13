import SwiftUI

/// Shared loading/error/empty footer keeps Feed and Explore behavior consistent.
struct ActivityListStatusView: View {
    @Environment(ActivityListViewModel.self) private var model
    @State private var showingCreate = false

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            if model.isLoading {
                ProgressView(model.hasLoaded ? "Refreshing activities…" : "Loading activities…")
            }
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red).multilineTextAlignment(.center)
                Button("Retry") { Task { await model.load(refresh: true) } }
                    .buttonStyle(.bordered).disabled(model.isLoading)
            } else if !model.isLoading, model.hasLoaded, model.visibleActivities.isEmpty {
                Image(systemName: "calendar.badge.plus").font(.largeTitle).foregroundStyle(AppColors.accent)
                Text(model.selectedCategoryId == nil ? "No activities yet" : "No activities in this category")
                    .font(AppTypography.headline)
                Text("Be the first to organize something after work.")
                    .foregroundStyle(AppColors.secondaryText).multilineTextAlignment(.center)
                Button("Create Activity") { showingCreate = true }.buttonStyle(.borderedProminent)
                if model.selectedCategoryId != nil {
                    Button("Show All Categories") { model.selectedCategoryId = nil }
                }
            }
            if model.hasMore, !model.isLoading {
                Button("Load More Activities") { Task { await model.load(more: true) } }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .sheet(isPresented: $showingCreate) { CreateActivityView(isPresentedAsSheet: true) }
    }
}
