import SwiftUI

struct ParticipantsView: View {
    let activityId: UUID
    @State private var engagement = ActivityEngagementViewModel()
    @State private var participants: [ParticipantDTO] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading { ProgressView("Loading participants…") }
            else if participants.isEmpty { ContentUnavailableView("No attendees yet", systemImage: "person.2") }
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
        .task {
            participants = await engagement.participants(activityId: activityId)
            isLoading = false
        }
        .refreshable { participants = await engagement.participants(activityId: activityId) }
    }
}
