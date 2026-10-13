import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var isEditing = false
    @State private var activities = ProfileActivitiesViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    VStack(spacing: AppSpacing.sm) {
                        AvatarView(initials: auth.profile?.initials ?? "", size: 88)
                            .accessibilityHidden(true)
                        Text(auth.profile?.displayName ?? "").font(AppTypography.title)
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
                    .padding(AppSpacing.lg)

                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("Interests").font(AppTypography.headline)
                        let selected = ActivityCategory.allCases.filter {
                            auth.profile?.interests?.contains($0.databaseSlug) == true
                        }
                        if selected.isEmpty { Text("Add interests in Edit Profile").foregroundStyle(.secondary) }
                        ForEach(selected) { category in
                            Label(category.displayName, systemImage: category.symbol)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button("Edit Profile") { auth.message = nil; isEditing = true }
                        .buttonStyle(.borderedProminent).disabled(auth.isBusy)

                    profileSection("Upcoming", symbol: "calendar", activities: activities.joined)
                    profileSection("Saved", symbol: "bookmark", activities: activities.saved)
                    profileSection("Created", symbol: "plus.circle", activities: activities.created)
                    if let error = activities.errorMessage { Text(error).foregroundStyle(.red) }
                    Button("Sign Out", role: .destructive) { Task { await auth.signOut() } }
                        .disabled(auth.isBusy)
                    if auth.isBusy { ProgressView() }
                    if let message = auth.message { Text(message).foregroundStyle(.red) }
                }
                .padding(AppSpacing.lg)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.appBackground)
            .navigationTitle("Profile")
            .task { await activities.load() }
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
                Text("No activities yet").font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
            } else {
                ForEach(activities) { activity in
                    NavigationLink { ActivityDetailsView(id: activity.id) } label: { ActivityRow(activity: activity) }
                        .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview { ProfileView().environment(AuthManager()) }
