import SwiftUI

struct ActivityDetailsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ActivityListViewModel.self) private var activities
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityDetailsViewModel
    @State private var engagement = ActivityEngagementViewModel()
    @State private var schedule = ActivityScheduleViewModel()
    @State private var isEditing = false
    @State private var confirmDelete = false

    init(id: UUID) { _model = State(initialValue: ActivityDetailsViewModel(id: id)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if model.isLoading { ProgressView("Loading activity…").frame(maxWidth: .infinity) }
                if let sourceActivity = model.activity {
                    let activity = engagement.state(for: sourceActivity)
                    ActivityCover(activity: activity).frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                    CategoryChip(category: activity.category, title: activity.categoryDisplayName)
                    Text(activity.title).font(AppTypography.title)
                    Label(activity.startsAt.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                    if let end = activity.endsAt {
                        Label("Ends \(end.formatted(date: .complete, time: .shortened))", systemImage: "clock")
                    }
                    Label(activity.locationName, systemImage: "mappin.and.ellipse")
                    if let address = activity.locationAddress { Text(address).foregroundStyle(.secondary) }
                    if !activity.description.isEmpty { Text(activity.description) }
                    HStack {
                        AvatarView(initials: activity.organizerInitials)
                        Text("Organized by \(activity.organizerName)")
                    }
                    HStack(spacing: AppSpacing.md) {
                        Button(activity.isSaved ? "Saved" : "Save", systemImage: activity.isSaved ? "bookmark.fill" : "bookmark") {
                            Task { await engagement.save(activityId: activity.id, isSaved: !activity.isSaved) }
                        }.buttonStyle(.bordered)
                        if activity.authorId == auth.userID {
                            Button("Organizer", systemImage: "checkmark.circle.fill") { }
                                .buttonStyle(.borderedProminent).disabled(true)
                        } else if activity.isGoing {
                            Button("Going", systemImage: "checkmark.circle.fill") {
                                Task {
                                    await engagement.leave(activityId: activity.id, organizerID: activity.authorId)
                                    if engagement.errorMessage == nil { schedule.cancelReminder(activityID: activity.id) }
                                }
                            }.buttonStyle(.borderedProminent)
                        } else {
                            let isFull = activity.maxParticipants.map { activity.participantCount >= $0 } ?? false
                            Button(isFull ? "Full" : "I'm Going", systemImage: "checkmark") {
                                Task { await engagement.join(activityId: activity.id) }
                            }.buttonStyle(.borderedProminent)
                                .disabled(isFull)
                        }
                    }
                    NavigationLink {
                        ParticipantsView(activityId: activity.id)
                    } label: {
                        HStack {
                            AvatarGroup(initials: activity.participantInitials, totalCount: activity.participantCount)
                            Text(activity.participationText)
                        }
                    }.buttonStyle(.plain)
                    if let error = engagement.errorMessage { Text(error).foregroundStyle(.red) }
                    if activity.isGoing || activity.authorId == auth.userID {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Calendar & Reminder").font(AppTypography.headline)
                            Button(schedule.isCalendarAdded ? "Added to Calendar" : "Add to Calendar",
                                   systemImage: schedule.isCalendarAdded ? "calendar.badge.checkmark" : "calendar.badge.plus") {
                                Task { await schedule.addOrUpdateCalendar(activity: activity) }
                            }.buttonStyle(.bordered).disabled(schedule.isBusy)
                            if schedule.isCalendarAdded {
                                Button("Remove Calendar Event", systemImage: "calendar.badge.minus") {
                                    Task { await schedule.removeCalendar(activityID: activity.id) }
                                }.buttonStyle(.bordered).disabled(schedule.isBusy)
                            }
                            Picker("Reminder", selection: Binding(
                                get: { schedule.reminder },
                                set: { option in Task { await schedule.setReminder(option, activity: activity) } }
                            )) {
                                ForEach(ActivityReminderOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }.disabled(schedule.isBusy)
                            if let error = schedule.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                        }
                        .padding(.top, AppSpacing.sm)
                    }
                    if activity.authorId == auth.userID {
                        Button("Edit Activity") { isEditing = true }.buttonStyle(.borderedProminent)
                            .disabled(model.isDeleting || model.isLoading)
                        Button("Delete Activity", role: .destructive) { confirmDelete = true }
                            .disabled(model.isDeleting || model.isLoading)
                    }
                }
                if let error = model.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button("Retry") { Task { await model.load() } }.disabled(model.isLoading || model.isDeleting)
                }
                if model.isDeleting { ProgressView("Deleting…") }
            }
            .padding(AppSpacing.lg).frame(maxWidth: 650).frame(maxWidth: .infinity, alignment: .center)
        }
        .background(AppColors.appBackground)
        .navigationTitle("Activity Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            if let activity = model.activity {
                await engagement.load(activityIDs: [activity.id])
                await schedule.configure(activity: engagement.state(for: activity))
            }
        }
        .refreshable {
            await model.load()
            if let activity = model.activity {
                await engagement.load(activityIDs: [activity.id])
                await schedule.configure(activity: engagement.state(for: activity))
            }
        }
        .onChange(of: model.needsAuthentication) { _, needed in
            if needed { Task { await auth.restore() } }
        }
        .sheet(isPresented: $isEditing) {
            if let activity = model.activity {
                CreateActivityView(activity: activity, isPresentedAsSheet: true) { saved in
                    model.didSave(saved)
                    Task { await schedule.didSave(activity: saved) }
                }
            }
        }
        .alert("Delete Activity?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    if await model.remove(userID: auth.userID) {
                        await schedule.removeAll(activityID: model.id)
                        activities.didDelete(id: model.id)
                        dismiss()
                    }
                }
            }
        } message: { Text("This activity will be removed.") }
    }
}
