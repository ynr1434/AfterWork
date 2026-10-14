import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var confirmSignOut = false
    @State private var isEditing = false
    @State private var activities = ProfileActivitiesViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.sm) {
                        AvatarView(initials: auth.profile?.initials ?? "", size: 88)
                            .accessibilityHidden(true)
                        Text(auth.profile?.displayName ?? "Your profile").font(AppTypography.title).multilineTextAlignment(.center)
                        if let title = auth.profile?.jobTitle { Text(title).font(AppTypography.headline) }
                        if let department = auth.profile?.department { Text(department)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.secondaryText)
                        }
                        if let email = auth.profile?.email ?? auth.email {
                            Text(email).font(AppTypography.body).foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(AppSpacing.lg).surfaceCard(radius: AppCornerRadius.large)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Interests").font(AppTypography.headline)
                        let selected = ActivityCategory.allCases.filter {
                            auth.profile?.interests?.contains($0.databaseSlug) == true
                        }
                        if selected.isEmpty { Text("Add interests in Edit Profile").foregroundStyle(.secondary) }
                        ForEach(selected) { category in
                            Label(category.displayName, systemImage: category.symbol)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(AppSpacing.md).surfaceCard()
                    SecondaryButton(title: "Edit Profile", symbol: "pencil") { auth.message = nil; isEditing = true }
                        .disabled(auth.isBusy)

                    if activities.isLoading && !activities.hasLoaded { ProgressView("Loading your activities…") }
                    profileSection("Upcoming", symbol: "calendar", activities: activities.joined)
                    profileSection("Saved", symbol: "bookmark", activities: activities.saved)
                    profileSection("Created", symbol: "plus.circle", activities: activities.created)
                    if let error = activities.errorMessage { InlineMessage(message: error) { Task { await activities.load() } }.disabled(activities.isLoading) }
                    PushSettingsView().padding(AppSpacing.md).surfaceCard()
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                        .frame(minHeight: 44).buttonStyle(.bordered)
                        .disabled(auth.isBusy)
                    if auth.isBusy { ProgressView() }
                    if let message = auth.message { InlineMessage(message: message) }
                }
                .padding(AppSpacing.lg)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.appBackground)
            .navigationTitle("Profile")
            .task { await activities.load() }
            .refreshable { await activities.load() }
            .confirmationDialog("Sign out of AfterWork?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
                Button("Cancel", role: .cancel) { }
            }
            .sheet(isPresented: $isEditing) { OnboardingView(isEditing: true).environment(auth) }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BackendDebugView()
                    } label: {
                        Label("Backend Connection", systemImage: "wrench.and.screwdriver")
                    }
                    .accessibilityLabel("Development: Backend Connection")
                }
            }
            #endif
        }
    }

    private func profileSection(_ title: String, symbol: String, activities: [Activity]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label(title, systemImage: symbol).font(AppTypography.headline)
            if activities.isEmpty {
                if self.activities.hasLoaded && self.activities.errorMessage == nil {
                    Text(title == "Upcoming" ? "Join a plan to see it here." : title == "Saved" ? "Save activities you'd like to come back to." : "Plans you organize will appear here.")
                        .font(.subheadline).foregroundStyle(AppColors.secondaryText)
                }
            } else {
                ForEach(activities) { activity in
                    NavigationLink { ActivityDetailsView(id: activity.id) } label: { ActivityRow(activity: activity) }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md).surfaceCard()
    }
}

#Preview { ProfileView().environment(AuthManager()).environment(PushNotificationManager.shared) }
