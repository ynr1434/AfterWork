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
                InlineMessage(message: error) { Task { await model.load(refresh: true) } }
                    .disabled(model.isLoading)
            } else if !model.isLoading, model.hasLoaded, model.visibleActivities.isEmpty {
                EmptyStateContent(icon: "calendar.badge.plus", title: model.selectedCategoryId == nil ? "Make the first plan" : "No plans in this category", subtitle: "Bring coworkers together for something you enjoy.")
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
