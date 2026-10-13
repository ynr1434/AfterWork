import SwiftUI

struct ProfileView: View {
    @Environment(AuthManager.self) private var auth
    @State private var isEditing = false
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

                    VStack(spacing: AppSpacing.md) {
                        statistic("Upcoming", symbol: "calendar", count: 3)
                        statistic("Created", symbol: "plus.circle", count: 2)
                        statistic("Joined", symbol: "person.2", count: 8)
                        statistic("Saved", symbol: "bookmark", count: 4)
                    }
                    Text("Activity counts are previews")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
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

    private func statistic(_ title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: AppSpacing.md) {
            Label(title, systemImage: symbol)
            Spacer(minLength: AppSpacing.sm)
            Text(count, format: .number).font(.title2.bold())
        }
        .font(AppTypography.headline)
        .padding(AppSpacing.lg)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)")
    }
}

#Preview { ProfileView().environment(AuthManager()) }
