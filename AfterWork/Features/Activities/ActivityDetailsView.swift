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
                if model.isLoading && model.activity == nil {
                    ProgressView("Loading activity…")
                        .frame(maxWidth: .infinity, minHeight: 220)
                }

                if let sourceActivity = model.activity {
                    let activity = engagement.state(for: sourceActivity)
                    hero(activity)
                    essentials(activity)
                    organizer(activity)

                    if !activity.description.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            sectionTitle("About this plan", symbol: "text.alignleft")
                            Text(activity.description)
                                .font(.body)
                                .foregroundStyle(AppColors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(AppSpacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surfaceCard()
                    }

                    participants(activity)
                    contentSection(title: "Photos", symbol: "photo.on.rectangle.angled") {
                        ActivityPhotosSection(activity: activity, model: photos)
                    }
                    contentSection(title: "Discussion", symbol: "text.bubble") {
                        ActivityCommentsSection(activityID: activity.id, model: comments)
                    }

                    if activity.isGoing || activity.authorId == auth.userID {
                        calendarSection(activity)
                    }

                    if activity.authorId == auth.userID {
                        organizerTools
                    }
                }

                if let error = model.errorMessage {
                    InlineMessage(message: error)
                    Button("Try again", systemImage: "arrow.clockwise") {
                        Task { await reload() }
                    }
                    .disabled(model.isLoading || model.isDeleting)
                }

                if model.isDeleting { ProgressView("Deleting activity…") }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)
            .padding(.bottom, AppSpacing.lg)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.appBackground)
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let sourceActivity = model.activity {
                engagementBar(engagement.state(for: sourceActivity))
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: engagement.isBusy) { _, busy in
            if !busy {
                activities.applyEngagement(engagement.states.filter { $0.key == model.id })
                if let activity = model.activity {
                    photos.updateAccess(activity: engagement.state(for: activity), currentUserID: auth.userID)
                }
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
        } message: {
            Text("This removes the activity and its discussion and photos for everyone. This cannot be undone.")
        }
        .alert("Delete Comment?", isPresented: Binding(
            get: { comments.pendingDelete != nil },
            set: { if !$0 { comments.pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { comments.pendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let comment = comments.pendingDelete else { return }
                comments.pendingDelete = nil
                Task { await comments.delete(comment) }
            }
        } message: {
            Text("This comment will be removed.")
        }
    }

    private func hero(_ activity: Activity) -> some View {
        ZStack(alignment: .bottomLeading) {
            ActivityCover(activity: activity)
                .frame(height: 350)

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.30), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .black.opacity(0.24), location: 0.52),
                    .init(color: .black.opacity(0.86), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Label(activity.categoryDisplayName, systemImage: activity.category.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial.opacity(0.82), in: Capsule())

                    Spacer()

                    if let capacity = activity.maxParticipants {
                        let remaining = max(0, capacity - activity.participantCount)
                        Label(remaining == 0 ? "Full" : "\(remaining) spots left", systemImage: remaining == 0 ? "person.2.fill" : "person.2")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(.black.opacity(0.38), in: Capsule())
                    }
                }

                Spacer(minLength: 24)

                Text(activity.title)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "calendar")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activity.startsAt.formatted(date: .complete, time: .omitted))
                            .font(.subheadline.weight(.semibold))
                        Text(activity.startsAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .foregroundStyle(.white)
                }
                .padding(.top, AppSpacing.md)
            }
            .padding(22)
        }
        .frame(height: 350)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 22, x: 0, y: 12)
        .accessibilityElement(children: .contain)
    }

    private func essentials(_ activity: Activity) -> some View {
        VStack(spacing: 0) {
            detailRow(
                symbol: "mappin.and.ellipse",
                tint: .orange,
                title: activity.locationName,
                subtitle: activity.locationAddress ?? "Location details"
            )

            Divider().padding(.leading, 58)

            detailRow(
                symbol: "clock.fill",
                tint: AppColors.accent,
                title: activity.endsAt.map { "\(activity.startsAt.formatted(date: .omitted, time: .shortened)) – \($0.formatted(date: .omitted, time: .shortened))" } ?? activity.startsAt.formatted(date: .omitted, time: .shortened),
                subtitle: activity.startsAt.formatted(date: .complete, time: .omitted)
            )
        }
        .padding(.horizontal, 18)
        .surfaceCard(radius: 24)
    }

    private func detailRow(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.primaryText)
                Text(subtitle).font(.caption).foregroundStyle(AppColors.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.md)
        .accessibilityElement(children: .combine)
    }

    private func organizer(_ activity: Activity) -> some View {
        HStack(spacing: AppSpacing.md) {
            AvatarView(initials: activity.organizerInitials, size: 48)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("HOSTED BY").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(AppColors.secondaryText)
                Text(activity.organizerName).font(.headline).foregroundStyle(AppColors.primaryText)
            }
            Spacer()
            if activity.authorId == auth.userID {
                Label("You", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(AppSpacing.md)
        .surfaceCard()
    }

    private func participants(_ activity: Activity) -> some View {
        NavigationLink { ParticipantsView(activityId: activity.id) } label: {
            HStack(spacing: AppSpacing.md) {
                AvatarGroup(initials: activity.participantInitials, totalCount: activity.participantCount)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(activity.participationText).font(.subheadline.weight(.semibold)).foregroundStyle(AppColors.primaryText)
                    Text("See who’s joining").font(.caption).foregroundStyle(AppColors.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(AppSpacing.md)
            .surfaceCard()
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
        }
        .buttonStyle(.plain)
        .accessibilityHint("View all participants")
    }

    private func contentSection<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionTitle(title, symbol: symbol)
            content()
        }
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.bold())
            .foregroundStyle(AppColors.primaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private func calendarSection(_ activity: Activity) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            sectionTitle("Calendar & reminders", symbol: "calendar.badge.clock")
            Button(schedule.isCalendarAdded ? "Added to Calendar" : "Add to Calendar", systemImage: schedule.isCalendarAdded ? "calendar.badge.checkmark" : "calendar.badge.plus") {
                Task { await schedule.addOrUpdateCalendar(activity: activity) }
            }
            .buttonStyle(.bordered)
            .disabled(schedule.isBusy)

            if schedule.isCalendarAdded {
                Button("Remove Calendar Event", systemImage: "calendar.badge.minus") {
                    Task { await schedule.removeCalendar(activityID: activity.id) }
                }
                .buttonStyle(.bordered)
                .disabled(schedule.isBusy)
            }

            Picker("Reminder", selection: Binding(
                get: { schedule.reminder },
                set: { option in Task { await schedule.setReminder(option, activity: activity) } }
            )) {
                ForEach(ActivityReminderOption.allCases) { option in Text(option.title).tag(option) }
            }
            .disabled(schedule.isBusy)

            if let error = schedule.errorMessage { InlineMessage(message: error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.md)
        .surfaceCard()
    }

    private var organizerTools: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionTitle("Organizer tools", symbol: "slider.horizontal.3")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.sm) {
                    editButton
                    deleteButton
                }
                VStack(spacing: AppSpacing.sm) {
                    editButton
                    deleteButton
                }
            }
        }
        .padding(AppSpacing.md)
        .surfaceCard()
    }

    private var editButton: some View {
        Button("Edit activity", systemImage: "pencil") { isEditing = true }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(model.isDeleting || model.isLoading)
    }

    private var deleteButton: some View {
        Button("Delete activity", systemImage: "trash", role: .destructive) { confirmDelete = true }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(model.isDeleting || model.isLoading)
    }

    private func engagementBar(_ activity: Activity) -> some View {
        VStack(spacing: AppSpacing.xs) {
            if let error = engagement.errorMessage { InlineMessage(message: error) }
            if engagement.isBusy { ProgressView("Updating activity…").font(.caption) }
            (typeSize.isAccessibilitySize
             ? AnyLayout(VStackLayout(spacing: AppSpacing.sm))
             : AnyLayout(HStackLayout(spacing: AppSpacing.md))) {
                Button {
                    Task { await engagement.save(activityId: activity.id, isSaved: !activity.isSaved) }
                } label: {
                    Label(activity.isSaved ? "Saved" : "Save", systemImage: activity.isSaved ? "bookmark.fill" : "bookmark")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)

                engagementPrimaryButton(activity)
            }
            .disabled(engagement.isBusy)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.sm)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Rectangle().fill(AppColors.separator).frame(height: 1) }
    }

    @ViewBuilder
    private func engagementPrimaryButton(_ activity: Activity) -> some View {
        if activity.authorId == auth.userID {
            Button {} label: {
                Label("You’re hosting", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.buttonFill)
            .disabled(true)
        } else if activity.isGoing {
            Button {
                Task {
                    await engagement.leave(activityId: activity.id, organizerID: activity.authorId)
                    if engagement.errorMessage == nil { schedule.cancelReminder(activityID: activity.id) }
                }
            } label: {
                Label("Going · Leave", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.buttonFill)
            .accessibilityHint("Leave this activity")
        } else {
            let isFull = activity.maxParticipants.map { activity.participantCount >= $0 } ?? false
            Button {
                Task { await engagement.join(activityId: activity.id) }
            } label: {
                Label(isFull ? "Activity full" : "Join", systemImage: "checkmark")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.buttonFill)
            .disabled(isFull)
        }
    }

    private func reload() async {
        await model.load()
        guard !Task.isCancelled, let activity = model.activity else { return }
        await engagement.load(activityIDs: [activity.id])
        let currentActivity = engagement.state(for: activity)
        activities.applyEngagement(engagement.states.filter { $0.key == activity.id })
        await schedule.configure(activity: currentActivity)
        await photos.load(activity: currentActivity, currentUserID: auth.userID)
        await comments.load(activityID: activity.id)
    }
}
