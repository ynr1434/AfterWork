import SwiftUI

struct ActivityDetailsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ActivityListViewModel.self) private var activities
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityDetailsViewModel
    @State private var engagement = ActivityEngagementViewModel()
    @State private var photos = ActivityPhotosViewModel()
    @State private var schedule = ActivityScheduleViewModel()
    @State private var comments = CommentsViewModel()
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
                    Text(activity.title).font(AppTypography.title).accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Label(activity.startsAt.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                    if let end = activity.endsAt { Label("Ends \(end.formatted(date: .complete, time: .shortened))", systemImage: "clock") }
                    Label(activity.locationName, systemImage: "mappin.and.ellipse")
                    if let address = activity.locationAddress { Text(address).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(AppSpacing.md).surfaceCard()
                    if !activity.description.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("About this activity").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            Text(activity.description).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        }
                    }
                    HStack { AvatarView(initials: activity.organizerInitials); Text("Organized by \(activity.organizerName)") }
                    engagementActions(activity).disabled(engagement.isBusy)
                    if engagement.isBusy { ProgressView("Updating activity…") }
                    NavigationLink { ParticipantsView(activityId: activity.id) } label: {
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.sm)) : AnyLayout(HStackLayout())) {
                            AvatarGroup(initials: activity.participantInitials, totalCount: activity.participantCount)
                            Text(activity.participationText)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                    }.buttonStyle(.plain).frame(minHeight: 44).accessibilityHint("View all participants")
                    Divider()
                    ActivityPhotosSection(activity: activity, model: photos)
                    Divider()
                    ActivityCommentsSection(activityID: activity.id, model: comments)
                    if let error = engagement.errorMessage { InlineMessage(message: error) }
                    if activity.isGoing || activity.authorId == auth.userID {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Calendar & Reminder").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                            Button(schedule.isCalendarAdded ? "Added to Calendar" : "Add to Calendar", systemImage: schedule.isCalendarAdded ? "calendar.badge.checkmark" : "calendar.badge.plus") {
                                Task { await schedule.addOrUpdateCalendar(activity: activity) }
                            }.buttonStyle(.bordered).disabled(schedule.isBusy)
                            if schedule.isCalendarAdded {
                                Button("Remove Calendar Event", systemImage: "calendar.badge.minus") { Task { await schedule.removeCalendar(activityID: activity.id) } }
                                    .buttonStyle(.bordered).disabled(schedule.isBusy)
                            }
                            Picker("Reminder", selection: Binding(get: { schedule.reminder }, set: { option in Task { await schedule.setReminder(option, activity: activity) } })) {
                                ForEach(ActivityReminderOption.allCases) { option in Text(option.title).tag(option) }
                            }.disabled(schedule.isBusy)
                            if let error = schedule.errorMessage { InlineMessage(message: error) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(AppSpacing.md).surfaceCard()
                    }
                    if activity.authorId == auth.userID {
                        Button("Edit Activity") { isEditing = true }.buttonStyle(.borderedProminent).tint(AppColors.buttonFill).foregroundStyle(.white).disabled(model.isDeleting || model.isLoading)
                        Button("Delete Activity", role: .destructive) { confirmDelete = true }.disabled(model.isDeleting || model.isLoading)
                    }
                }
                if let error = model.errorMessage {
                    InlineMessage(message: error)
                    Button("Retry") { Task { await model.load() } }.disabled(model.isLoading || model.isDeleting)
                }
                if model.isDeleting { ProgressView("Deleting…") }
            }
            .padding(AppSpacing.lg).frame(maxWidth: 650).frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.appBackground)
        .navigationTitle("Activity Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            if let activity = model.activity {
                await engagement.load(activityIDs: [activity.id])
                let currentActivity = engagement.state(for: activity)
                await schedule.configure(activity: currentActivity)
                await photos.load(activity: currentActivity, currentUserID: auth.userID)
                await comments.load(activityID: activity.id)
            }
        }
        .refreshable {
            await model.load()
            if let activity = model.activity {
                await engagement.load(activityIDs: [activity.id])
                let currentActivity = engagement.state(for: activity)
                await schedule.configure(activity: currentActivity)
                await photos.load(activity: currentActivity, currentUserID: auth.userID)
                await comments.load(activityID: activity.id)
            }
        }
        .onChange(of: engagement.isBusy) { _, busy in
            if !busy {
                activities.applyEngagement(engagement.states)
                if let activity = model.activity { photos.updateAccess(activity: engagement.state(for: activity), currentUserID: auth.userID) }
            }
        }
        .onChange(of: model.needsAuthentication) { _, needed in if needed { Task { await auth.restore() } } }
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
        } message: { Text("This removes the activity and its discussion and photos for everyone. This cannot be undone.") }
        .alert("Delete Comment?", isPresented: Binding(get: { comments.pendingDelete != nil }, set: { if !$0 { comments.pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { comments.pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let comment = comments.pendingDelete else { return }
                comments.pendingDelete = nil
                Task { await comments.delete(comment) }
            }
        } message: { Text("This comment will be removed.") }
    }


    private func engagementActions(_ activity: Activity) -> some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.sm)) : AnyLayout(HStackLayout(spacing: AppSpacing.md))) {
                        Button(activity.isSaved ? "Saved" : "Save", systemImage: activity.isSaved ? "bookmark.fill" : "bookmark") {
                            Task { await engagement.save(activityId: activity.id, isSaved: !activity.isSaved) }
                        }.buttonStyle(.bordered)
                        if activity.authorId == auth.userID {
                            Button("Organizer", systemImage: "checkmark.circle.fill") { }.buttonStyle(.borderedProminent).tint(AppColors.buttonFill).foregroundStyle(.white).disabled(true)
                        } else if activity.isGoing {
                            Button("Going", systemImage: "checkmark.circle.fill") {
                                Task {
                                    await engagement.leave(activityId: activity.id, organizerID: activity.authorId)
                                    if engagement.errorMessage == nil { schedule.cancelReminder(activityID: activity.id) }
                                }
                            }.buttonStyle(.borderedProminent).tint(AppColors.buttonFill).foregroundStyle(.white)
                        } else {
                            let isFull = activity.maxParticipants.map { activity.participantCount >= $0 } ?? false
                            Button(isFull ? "Full" : "I'm Going", systemImage: "checkmark") { Task { await engagement.join(activityId: activity.id) } }
                                .buttonStyle(.borderedProminent).tint(AppColors.buttonFill).foregroundStyle(.white).disabled(isFull)
                        }
                    }
    }
}
