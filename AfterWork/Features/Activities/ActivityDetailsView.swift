import SwiftUI

struct ActivityDetailsView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(ActivityListViewModel.self) private var activities
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
                    Text(activity.title).font(AppTypography.title)
                    Label(activity.startsAt.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                    if let end = activity.endsAt { Label("Ends \(end.formatted(date: .complete, time: .shortened))", systemImage: "clock") }
                    Label(activity.locationName, systemImage: "mappin.and.ellipse")
                    if let address = activity.locationAddress { Text(address).foregroundStyle(.secondary) }
                    if !activity.description.isEmpty { Text(activity.description) }
                    HStack { AvatarView(initials: activity.organizerInitials); Text("Organized by \(activity.organizerName)") }
                    HStack(spacing: AppSpacing.md) {
                        Button(activity.isSaved ? "Saved" : "Save", systemImage: activity.isSaved ? "bookmark.fill" : "bookmark") {
                            Task { await engagement.save(activityId: activity.id, isSaved: !activity.isSaved) }
                        }.buttonStyle(.bordered)
                        if activity.authorId == auth.userID {
                            Button("Organizer", systemImage: "checkmark.circle.fill") { }.buttonStyle(.borderedProminent).disabled(true)
                        } else if activity.isGoing {
                            Button("Going", systemImage: "checkmark.circle.fill") {
                                Task {
                                    await engagement.leave(activityId: activity.id, organizerID: activity.authorId)
                                    if engagement.errorMessage == nil { schedule.cancelReminder(activityID: activity.id) }
                                }
                            }.buttonStyle(.borderedProminent)
                        } else {
                            let isFull = activity.maxParticipants.map { activity.participantCount >= $0 } ?? false
                            Button(isFull ? "Full" : "I'm Going", systemImage: "checkmark") { Task { await engagement.join(activityId: activity.id) } }
                                .buttonStyle(.borderedProminent).disabled(isFull)
                        }
                    }
                    NavigationLink { ParticipantsView(activityId: activity.id) } label: {
                        HStack { AvatarGroup(initials: activity.participantInitials, totalCount: activity.participantCount); Text(activity.participationText) }
                    }.buttonStyle(.plain)
                    ActivityPhotosSection(activity: activity, model: photos)
                    commentsSection(activityID: activity.id)
                    if let error = engagement.errorMessage { Text(error).foregroundStyle(.red) }
                    if activity.isGoing || activity.authorId == auth.userID {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("Calendar & Reminder").font(AppTypography.headline)
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
                            if let error = schedule.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
                        }.padding(.top, AppSpacing.sm)
                    }
                    if activity.authorId == auth.userID {
                        Button("Edit Activity") { isEditing = true }.buttonStyle(.borderedProminent).disabled(model.isDeleting || model.isLoading)
                        Button("Delete Activity", role: .destructive) { confirmDelete = true }.disabled(model.isDeleting || model.isLoading)
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
        } message: { Text("This activity will be removed.") }
        .alert("Delete Comment?", isPresented: Binding(get: { comments.pendingDelete != nil }, set: { if !$0 { comments.pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { comments.pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let comment = comments.pendingDelete else { return }
                comments.pendingDelete = nil
                Task { await comments.delete(comment) }
            }
        } message: { Text("This comment will be removed.") }
    }

    @ViewBuilder
    private func commentsSection(activityID: UUID) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack {
                Text("Discussion").font(AppTypography.headline)
                Text("· \(comments.comments.count)").foregroundStyle(.secondary)
            }
            if comments.isLoading && comments.comments.isEmpty { ProgressView() }
            else if comments.comments.isEmpty { Text("No comments yet. Start the conversation.").foregroundStyle(.secondary) }
            else { ForEach(comments.comments) { comment in commentRow(comment) } }
            if let error = comments.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            if !comments.suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(comments.suggestions) { suggestion in
                        Button { comments.selectSuggestion(suggestion) } label: {
                            HStack { AvatarView(initials: suggestion.initials, size: 28); Text("@\(suggestion.name)"); Spacer() }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, AppSpacing.sm).background(AppColors.surface).clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
            }
            HStack(alignment: .bottom, spacing: AppSpacing.sm) {
                TextField(comments.editingComment == nil ? "Add a comment…" : "Edit comment…", text: $comments.draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.roundedBorder).onChange(of: comments.draft) { _, _ in comments.updateSuggestions() }
                Button { Task { await comments.submit(activityID: activityID) } } label: {
                    Image(systemName: comments.isSending ? "hourglass" : "paperplane.fill")
                }.buttonStyle(.borderedProminent).disabled(comments.isSending || comments.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if comments.editingComment != nil { Button("Cancel editing") { comments.cancelEditing() }.font(.footnote) }
        }.padding(.top, AppSpacing.sm)
    }

    @ViewBuilder
    private func commentRow(_ comment: Comment) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            AvatarView(initials: comment.authorInitials, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(comment.authorName).font(.subheadline.weight(.semibold))
                    Text(comment.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                }
                Text(mentionAttributedString(comment.body)).font(.body)
                if comment.isEdited { Text("Edited").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .contextMenu {
            if comment.authorId == auth.userID {
                Button("Edit", systemImage: "pencil") { comments.beginEditing(comment) }
                Button("Delete", systemImage: "trash", role: .destructive) { comments.pendingDelete = comment }
            }
        }
    }

    private func mentionAttributedString(_ body: String) -> AttributedString {
        var result = AttributedString(body)
        for token in body.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) where token.first == "@" {
            if let range = result.range(of: String(token)) {
                result[range].foregroundColor = .blue
                result[range].font = .body.bold()
            }
        }
        return result
    }
}
