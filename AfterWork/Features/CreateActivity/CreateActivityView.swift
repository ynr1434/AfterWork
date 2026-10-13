import SwiftUI

struct CreateActivityView: View {
    @State private var showsPreviewMessage = false

    var body: some View {
        NavigationStack {
            EmptyStateView(
                icon: "plus.circle.fill",
                title: "Create an activity",
                subtitle: "Invite coworkers to join you after work."
            )
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Create activity", symbol: "plus") {
                    showsPreviewMessage = true
                }
                .frame(maxWidth: 500)
                .padding(AppSpacing.lg)
                .background(AppColors.appBackground)
            }
            .navigationTitle("Create")
            .alert("Your next plan starts here", isPresented: $showsPreviewMessage) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Activity creation is coming in a future update.")
            }
        }
    }
}

#Preview { CreateActivityView() }
