import SwiftUI

struct ParticipantsView: View {
    let activityId: UUID
    @State private var engagement = ActivityEngagementViewModel()
    @State private var participants: [ParticipantDTO] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Loading participants…") }
            else if let error = engagement.errorMessage {
                VStack { InlineMessage(message: error) { Task { await load() } } }.padding()
            }
            else if participants.isEmpty { EmptyStateView(icon: "person.2", title: "Good company starts with you", subtitle: "People who join this activity will appear here.") }
            else {
                List(participants) { participant in
                    HStack(spacing: AppSpacing.md) {
                        AvatarView(initials: participant.initials)
                        VStack(alignment: .leading) {
                            Text(participant.profile?.displayName ?? "AfterWork member")
                            if let role = participant.profile?.jobTitle ?? participant.profile?.department {
                                Text(role).font(AppTypography.caption).foregroundStyle(AppColors.secondaryText)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Participants")
        .background(AppColors.appBackground)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        participants = await engagement.participants(activityId: activityId)
        isLoading = false
    }
}
